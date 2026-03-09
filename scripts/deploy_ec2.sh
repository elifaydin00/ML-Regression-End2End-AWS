#!/bin/bash
# Deploy script sent to EC2 via SSM.
# REPO_URL must be set in the environment before calling this script.
set -e

if [ -z "$REPO_URL" ]; then
  echo "ERROR: REPO_URL not set" && exit 1
fi

if [ ! -d "/opt/housing-ml/app/.git" ]; then
  echo "=== Fresh EC2: bootstrapping ==="
  mkdir -p /opt/housing-ml /var/log/housing-ml
  chown ec2-user:ec2-user /opt/housing-ml /var/log/housing-ml

  sudo -u ec2-user git clone "$REPO_URL" /opt/housing-ml/app

  # Install uv for ec2-user if not present
  if [ ! -f "/home/ec2-user/.local/bin/uv" ]; then
    sudo -u ec2-user bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi

  # Create run_api.sh
  cat > /opt/housing-ml/run_api.sh << 'APIEOF'
#!/bin/bash
export USE_S3=true
export S3_BUCKET=house-forecast
export AWS_REGION=us-east-1
export PYTHONPATH=/opt/housing-ml/app
cd /opt/housing-ml/app
aws s3 sync "s3://house-forecast/models/production/" models/ || true
/opt/housing-ml/app/.venv/bin/uvicorn src.api.main:app --host 0.0.0.0 --port 8000 >> /var/log/housing-ml/api.log 2>&1
APIEOF
  chmod +x /opt/housing-ml/run_api.sh

  # Create systemd service
  cat > /etc/systemd/system/housing-ml-api.service << 'SVCEOF'
[Unit]
Description=Housing ML FastAPI Service
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/housing-ml
Environment="USE_S3=true"
Environment="S3_BUCKET=house-forecast"
Environment="AWS_REGION=us-east-1"
Environment="PYTHONPATH=/opt/housing-ml/app"
ExecStart=/opt/housing-ml/run_api.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF
  systemctl daemon-reload
  systemctl enable housing-ml-api
  echo "=== Bootstrap complete ==="

else
  echo "=== Existing install: pulling latest code ==="
  git -C /opt/housing-ml/app remote set-url origin "$REPO_URL"
  git -C /opt/housing-ml/app pull origin main
fi

# Sync deps (creates .venv on first run)
sudo -u ec2-user bash -c "cd /opt/housing-ml/app && /home/ec2-user/.local/bin/uv sync --quiet"

# Start or restart the API
systemctl restart housing-ml-api
sleep 5
systemctl is-active housing-ml-api && echo DEPLOY_OK
