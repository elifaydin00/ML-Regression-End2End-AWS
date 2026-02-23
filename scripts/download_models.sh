#!/bin/bash
# Download latest models from S3 on container startup

set -e

echo "📥 Downloading latest models from S3..."
echo "Bucket: ${S3_BUCKET}"
echo "Region: ${AWS_REGION}"

# Download production models
aws s3 cp s3://${S3_BUCKET}/models/production/xgb_model_latest.pkl models/xgb_best_model.pkl --region ${AWS_REGION} || {
    echo "⚠️ Warning: Could not download xgb_model_latest.pkl, checking for fallback..."
    aws s3 cp s3://${S3_BUCKET}/models/xgb_best_model.pkl models/xgb_best_model.pkl --region ${AWS_REGION} || echo "⚠️ Model not found in S3"
}

# Download encoders
aws s3 cp s3://${S3_BUCKET}/models/production/freq_encoder_latest.pkl models/freq_encoder.pkl --region ${AWS_REGION} 2>/dev/null || {
    echo "⚠️ freq_encoder_latest.pkl not found, trying fallback..."
    aws s3 cp s3://${S3_BUCKET}/models/freq_encoder.pkl models/freq_encoder.pkl --region ${AWS_REGION} 2>/dev/null || echo "⚠️ freq_encoder.pkl not found"
}

aws s3 cp s3://${S3_BUCKET}/models/production/target_encoder_latest.pkl models/target_encoder.pkl --region ${AWS_REGION} 2>/dev/null || {
    echo "⚠️ target_encoder_latest.pkl not found, trying fallback..."
    aws s3 cp s3://${S3_BUCKET}/models/target_encoder.pkl models/target_encoder.pkl --region ${AWS_REGION} 2>/dev/null || echo "⚠️ target_encoder.pkl not found"
}

# Download feature engineered training data for schema alignment
aws s3 cp s3://${S3_BUCKET}/processed/feature_engineered_train.csv data/processed/feature_engineered_train.csv --region ${AWS_REGION} 2>/dev/null || {
    echo "⚠️ feature_engineered_train.csv not found in S3"
}

echo "✅ Model download complete!"
ls -lh models/ || echo "Models directory contents not available"

