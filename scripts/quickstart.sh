#!/bin/bash
# Quick start script for local development and testing

set -e

echo "🚀 Housing Regression ML - Quick Start"
echo "======================================"

# Check if uv is installed
if ! command -v uv &> /dev/null; then
    echo "❌ uv is not installed. Installing..."
    pip install uv
fi

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
uv sync

# Check if data exists
if [ ! -f "data/raw/HouseTS.csv" ]; then
    echo ""
    echo "⚠️  Warning: Raw data not found at data/raw/HouseTS.csv"
    echo "   Please add your dataset before proceeding."
    exit 1
fi

# Run data pipeline
echo ""
echo "📊 Running data pipeline..."
echo "  1. Loading and splitting data..."
uv run python src/feature_pipeline/load.py

echo "  2. Preprocessing data..."
uv run python src/feature_pipeline/preprocess.py

echo "  3. Feature engineering..."
uv run python src/feature_pipeline/feature_engineering.py

# Train model locally
echo ""
echo "🏋️  Training model locally..."
export USE_S3=false
uv run python src/training_pipeline/train.py

# Run tests
echo ""
echo "🧪 Running tests..."
uv run pytest tests/ -v || echo "⚠️  Some tests failed"

# Start API
echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the API locally, run:"
echo "  uv run uvicorn src.api.main:app --reload"
echo ""
echo "To upload data to S3, run:"
echo "  export S3_BUCKET=your-bucket-name"
echo "  export AWS_REGION=us-east-1"
echo "  uv run python src/data/upload_to_s3.py"
echo ""
echo "To train on AWS:"
echo "  export USE_S3=true"
echo "  uv run python src/training_pipeline/train.py"

