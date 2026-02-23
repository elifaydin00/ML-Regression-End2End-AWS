#!/bin/bash
# Build and push Docker images to AWS ECR

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
TRAINING_REPO="housing-training"
API_REPO="housing-api"

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Error: AWS_ACCOUNT_ID environment variable is not set"
    echo "Usage: AWS_ACCOUNT_ID=123456789 ./scripts/build_and_push.sh"
    exit 1
fi

echo "🔧 Building and pushing Docker images..."
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"

# Login to ECR
echo "🔐 Logging in to ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push training image
echo "🏗️ Building training image..."
docker build -t $TRAINING_REPO:latest -f Dockerfile.train .

echo "🏷️ Tagging training image..."
docker tag $TRAINING_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TRAINING_REPO:latest
docker tag $TRAINING_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TRAINING_REPO:$(date +%Y%m%d_%H%M%S)

echo "⬆️ Pushing training image..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TRAINING_REPO:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TRAINING_REPO:$(date +%Y%m%d_%H%M%S)

# Build and push API image
echo "🏗️ Building API image..."
docker build -t $API_REPO:latest -f Dockerfile .

echo "🏷️ Tagging API image..."
docker tag $API_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$API_REPO:latest
docker tag $API_REPO:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$API_REPO:$(date +%Y%m%d_%H%M%S)

echo "⬆️ Pushing API image..."
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$API_REPO:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$API_REPO:$(date +%Y%m%d_%H%M%S)

echo "✅ All images built and pushed successfully!"
echo ""
echo "Training image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$TRAINING_REPO:latest"
echo "API image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$API_REPO:latest"

