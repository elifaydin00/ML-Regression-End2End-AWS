#!/bin/bash
set -e

echo "=== Housing ML Training Pipeline ==="
echo "Started at $(date)"
echo "USE_S3=${USE_S3:-false}, S3_BUCKET=${S3_BUCKET:-unset}"

PYTHON="uv run python"

echo "--- [1/4] Loading data ---"
$PYTHON src/feature_pipeline/load.py

echo "--- [2/4] Preprocessing ---"
$PYTHON src/feature_pipeline/preprocess.py

echo "--- [3/4] Feature engineering ---"
$PYTHON src/feature_pipeline/feature_engineering.py

echo "--- [4/4] Hyperparameter tuning & training ---"
$PYTHON src/training_pipeline/tune.py

if [ "${USE_S3}" = "true" ]; then
    echo "--- Uploading models to S3: s3://${S3_BUCKET}/models/production/ ---"
    aws s3 cp models/xgb_best_model.pkl "s3://${S3_BUCKET}/models/production/xgb_model_latest.pkl"
    aws s3 cp models/freq_encoder.pkl    "s3://${S3_BUCKET}/models/production/freq_encoder_latest.pkl"
    aws s3 cp models/target_encoder.pkl  "s3://${S3_BUCKET}/models/production/target_encoder_latest.pkl"
    echo "Models uploaded successfully"

    # Signal the API EC2 to reload the new model from S3
    if [ -n "${API_INSTANCE_ID}" ]; then
        echo "--- Sending restart command to API EC2: ${API_INSTANCE_ID} ---"
        aws ssm send-command \
            --region "${AWS_DEFAULT_REGION:-us-east-1}" \
            --instance-ids "${API_INSTANCE_ID}" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["sudo systemctl restart housing-ml-api"]' \
            --comment "Reload model after monthly training" \
            --output text
        echo "API restart command sent"
    fi
fi

echo "=== Training complete at $(date) ==="
