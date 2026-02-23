#!/bin/bash
# Build Lambda deployment package for training trigger

set -e

cd "$(dirname "$0")"

echo "📦 Building Lambda deployment package..."

# Create temporary directory
rm -rf lambda_package lambda_trigger.zip
mkdir lambda_package

# Copy Lambda function
cp lambda_trigger.py lambda_package/index.py

# Create zip file
cd lambda_package
zip -r ../lambda_trigger.zip .
cd ..

# Cleanup
rm -rf lambda_package

echo "✅ Lambda package created: lambda_trigger.zip"
ls -lh lambda_trigger.zip

