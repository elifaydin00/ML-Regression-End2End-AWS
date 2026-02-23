#!/bin/bash
# Deploy application to EC2 instance

set -e

# Configuration
EC2_IP="${EC2_IP:-}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/housing-ml-key.pem}"
APP_DIR="/opt/housing-ml/app"

if [ -z "$EC2_IP" ]; then
    echo "Error: EC2_IP environment variable is not set"
    echo "Usage: EC2_IP=1.2.3.4 ./scripts/deploy_to_ec2.sh"
    exit 1
fi

echo "🚀 Deploying to EC2: $EC2_IP"
echo "SSH Key: $SSH_KEY"

# Create app directory on EC2 if it doesn't exist
ssh -i "$SSH_KEY" ec2-user@$EC2_IP "sudo mkdir -p $APP_DIR && sudo chown ec2-user:ec2-user $APP_DIR"

# Sync code to EC2 (excluding unnecessary files)
echo "📦 Syncing code to EC2..."
rsync -avz --progress \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.pytest_cache' \
    --exclude='data/' \
    --exclude='models/' \
    --exclude='.venv' \
    --exclude='venv' \
    --exclude='*.egg-info' \
    -e "ssh -i $SSH_KEY" \
    ./ ec2-user@$EC2_IP:$APP_DIR/

# Install dependencies on EC2
echo "📥 Installing dependencies..."
ssh -i "$SSH_KEY" ec2-user@$EC2_IP << 'EOF'
cd /opt/housing-ml/app

# Install uv if not present
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Create virtual environment and install dependencies
if [ ! -d "venv" ]; then
    python3.11 -m venv venv
fi

source venv/bin/activate
uv pip install -e .

# Create models directory
mkdir -p models

# Download models from S3 if USE_S3 is enabled
if [ "$USE_S3" = "true" ] && [ -n "$S3_BUCKET" ]; then
    echo "📥 Downloading models from S3..."
    aws s3 sync s3://$S3_BUCKET/models/ models/ || echo "⚠️ No models in S3 yet"
fi

echo "✅ Dependencies installed"
EOF

# Restart API service
echo "🔄 Restarting API service..."
ssh -i "$SSH_KEY" ec2-user@$EC2_IP "sudo systemctl restart housing-ml-api || echo '⚠️ Service not yet configured. Start manually with: uvicorn src.api.main:app --host 0.0.0.0 --port 8000'"

echo "✅ Deployment complete!"
echo ""
echo "API URL: http://$EC2_IP:8000"
echo "API Docs: http://$EC2_IP:8000/docs"
echo ""
echo "To view logs:"
echo "  ssh -i $SSH_KEY ec2-user@$EC2_IP 'tail -f /var/log/housing-ml/api.log'"

