#!/bin/bash
# User data script for EC2 instance initialization
# This script runs on instance launch and sets up the ML environment

set -e

# Variables from Terraform
S3_BUCKET="${s3_bucket}"
AWS_REGION="${aws_region}"
LOG_GROUP="${log_group}"
GITHUB_REPO_URL="${github_repo_url}"

echo "Starting Housing ML EC2 setup..."

# Update system
sudo dnf update -y

# Install Docker
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Python 3.11 and pip
sudo dnf install -y python3.11 python3.11-pip git

# Install uv for faster Python package management
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="/root/.cargo/bin:$HOME/.cargo/bin:$PATH"

# Install AWS CLI v2 (if not already installed)
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
fi

# Install CloudWatch Logs agent
sudo dnf install -y amazon-cloudwatch-agent

# Configure CloudWatch Logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/housing-ml/api.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "api"
          },
          {
            "file_path": "/var/log/housing-ml/training.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "training"
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

# Create app directory
sudo mkdir -p /opt/housing-ml
sudo chown ec2-user:ec2-user /opt/housing-ml

# Create log directory
sudo mkdir -p /var/log/housing-ml
sudo chown ec2-user:ec2-user /var/log/housing-ml

# Clone repository and set up Python environment
cd /opt/housing-ml
git clone "$GITHUB_REPO_URL" app
cd app

# Create virtual environment and install dependencies using uv
/root/.cargo/bin/uv venv .venv
/root/.cargo/bin/uv sync
sudo chown -R ec2-user:ec2-user /opt/housing-ml

cat > /opt/housing-ml/run_api.sh <<'SCRIPT'
#!/bin/bash
# Run the FastAPI application

export USE_S3=true
export S3_BUCKET=S3_BUCKET_PLACEHOLDER
export AWS_REGION=AWS_REGION_PLACEHOLDER
export PYTHONPATH=/opt/housing-ml/app

cd /opt/housing-ml/app

# Download models from S3 if not present
if [ ! -f "models/xgb_best_model.pkl" ]; then
    echo "Downloading models from S3..."
    aws s3 sync "s3://$${S3_BUCKET}/models/production/" models/ || true
fi

# Start API
/opt/housing-ml/app/.venv/bin/uvicorn src.api.main:app --host 0.0.0.0 --port 8000 >> /var/log/housing-ml/api.log 2>&1
SCRIPT

# Substitute real values into the placeholder script
sed -i "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" /opt/housing-ml/run_api.sh
sed -i "s/AWS_REGION_PLACEHOLDER/$AWS_REGION/g" /opt/housing-ml/run_api.sh
chmod +x /opt/housing-ml/run_api.sh

cat > /opt/housing-ml/run_training.sh <<'SCRIPT'
#!/bin/bash
# Run full training pipeline: feature engineering → tune → upload → restart API

export USE_S3=true
export S3_BUCKET=S3_BUCKET_PLACEHOLDER
export AWS_REGION=AWS_REGION_PLACEHOLDER
export MLFLOW_TRACKING_URI=sqlite:////tmp/mlflow.db
export MLFLOW_ARTIFACT_ROOT=s3://S3_BUCKET_PLACEHOLDER/mlflow/artifacts
export PYTHONPATH=/opt/housing-ml/app

cd /opt/housing-ml/app

echo "Starting training pipeline at $(date)" >> /var/log/housing-ml/training.log

# Feature pipeline
/opt/housing-ml/app/.venv/bin/python src/feature_pipeline/load.py >> /var/log/housing-ml/training.log 2>&1
/opt/housing-ml/app/.venv/bin/python src/feature_pipeline/preprocess.py >> /var/log/housing-ml/training.log 2>&1
/opt/housing-ml/app/.venv/bin/python src/feature_pipeline/feature_engineering.py >> /var/log/housing-ml/training.log 2>&1

# Tune: Optuna finds best params, retrains best model, saves models/xgb_best_model.pkl
/opt/housing-ml/app/.venv/bin/python src/training_pipeline/tune.py >> /var/log/housing-ml/training.log 2>&1

# Upload tuned model to S3 under the key the API reads at startup
aws s3 cp models/xgb_best_model.pkl \
    s3://${S3_BUCKET}/models/production/xgb_model_latest.pkl >> /var/log/housing-ml/training.log 2>&1

# Clear local cache so API downloads fresh model on restart
rm -f /opt/housing-ml/app/models/xgb_best_model.pkl

echo "Training completed at $(date)" >> /var/log/housing-ml/training.log

# Restart API — startup event pulls new model from S3
sudo systemctl restart housing-ml-api

echo "API restarted with new model at $(date)" >> /var/log/housing-ml/training.log
SCRIPT

sed -i "s/S3_BUCKET_PLACEHOLDER/$S3_BUCKET/g" /opt/housing-ml/run_training.sh
sed -i "s/AWS_REGION_PLACEHOLDER/$AWS_REGION/g" /opt/housing-ml/run_training.sh
chmod +x /opt/housing-ml/run_training.sh

# Create systemd service for API
cat > /etc/systemd/system/housing-ml-api.service <<EOF
[Unit]
Description=Housing ML FastAPI Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/housing-ml
Environment="USE_S3=true"
Environment="S3_BUCKET=$S3_BUCKET"
Environment="AWS_REGION=$AWS_REGION"
ExecStart=/opt/housing-ml/run_api.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable housing-ml-api
sudo systemctl start housing-ml-api

# Create cron job for monthly training (1st of month at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 1 * * /opt/housing-ml/run_training.sh") | crontab -

echo "Housing ML EC2 setup complete!"
echo "S3 Bucket: $S3_BUCKET"
echo "AWS Region: $AWS_REGION"
echo "Log Group: $LOG_GROUP"
echo "Repo: $GITHUB_REPO_URL"
