"""
Train a baseline XGBoost model.

- Reads feature-engineered train/eval CSVs from S3 or local.
- Trains XGBRegressor.
- Returns metrics and saves model to S3 and local `model_output`.
"""

from __future__ import annotations
from pathlib import Path
from typing import Dict, Optional
import os
import logging

import numpy as np
import pandas as pd
from joblib import dump
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from xgboost import XGBRegressor
import boto3
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# AWS Configuration
S3_BUCKET = os.getenv("S3_BUCKET", "house-forecast")
AWS_REGION = os.getenv("AWS_REGION")  # reads from ~/.aws/config when not set
USE_S3 = os.getenv("USE_S3", "false").lower() == "true"

DEFAULT_TRAIN = Path("data/processed/feature_engineered_train.csv")
DEFAULT_EVAL = Path("data/processed/feature_engineered_eval.csv")
DEFAULT_OUT = Path("models/xgb_model.pkl")


def download_from_s3(s3_key: str, local_path: Path) -> Path:
    """Download file from S3 to local path."""
    if not USE_S3:
        return local_path

    s3_client = boto3.client("s3", region_name=AWS_REGION)
    local_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        logger.info(f"📥 Downloading s3://{S3_BUCKET}/{s3_key} to {local_path}")
        s3_client.download_file(S3_BUCKET, s3_key, str(local_path))
        logger.info(f"✅ Downloaded {s3_key}")
    except Exception as e:
        logger.error(f"❌ Failed to download {s3_key}: {e}")
        raise

    return local_path


def upload_to_s3(local_path: Path, s3_key: str) -> str:
    """Upload file from local path to S3."""
    if not USE_S3:
        logger.info("S3 upload skipped (USE_S3=false)")
        return str(local_path)

    s3_client = boto3.client("s3", region_name=AWS_REGION)

    try:
        logger.info(f"📤 Uploading {local_path} to s3://{S3_BUCKET}/{s3_key}")
        s3_client.upload_file(str(local_path), S3_BUCKET, s3_key)
        logger.info(f"✅ Uploaded to {s3_key}")
        return f"s3://{S3_BUCKET}/{s3_key}"
    except Exception as e:
        logger.error(f"❌ Failed to upload {s3_key}: {e}")
        raise


def _maybe_sample(df: pd.DataFrame, sample_frac: Optional[float], random_state: int) -> pd.DataFrame:
    if sample_frac is None:
        return df
    sample_frac = float(sample_frac)
    if sample_frac <= 0 or sample_frac >= 1:
        return df
    return df.sample(frac=sample_frac, random_state=random_state).reset_index(drop=True)


def train_model(
    train_path: Path | str = DEFAULT_TRAIN,
    eval_path: Path | str = DEFAULT_EVAL,
    model_output: Path | str = DEFAULT_OUT,
    model_params: Optional[Dict] = None,
    sample_frac: Optional[float] = None,
    random_state: int = 42,
    upload_to_s3_enabled: bool = USE_S3,
):
    """Train baseline XGB and save model locally and to S3.

    Returns
    -------
    model : XGBRegressor
    metrics : dict[str, float]
    """
    logger.info("🚀 Starting training pipeline...")
    logger.info(f"Environment: USE_S3={USE_S3}, S3_BUCKET={S3_BUCKET}, AWS_REGION={AWS_REGION}")

    # Download data from S3 if enabled
    train_path = Path(train_path)
    eval_path = Path(eval_path)

    if USE_S3:
        train_path = download_from_s3(f"processed/{train_path.name}", train_path)
        eval_path = download_from_s3(f"processed/{eval_path.name}", eval_path)

    logger.info(f"📂 Loading training data from {train_path}")
    train_df = pd.read_csv(train_path)
    logger.info(f"📂 Loading evaluation data from {eval_path}")
    eval_df = pd.read_csv(eval_path)

    train_df = _maybe_sample(train_df, sample_frac, random_state)
    eval_df = _maybe_sample(eval_df, sample_frac, random_state)

    logger.info(f"Train shape: {train_df.shape}, Eval shape: {eval_df.shape}")

    target = "price"
    X_train, y_train = train_df.drop(columns=[target]), train_df[target]
    X_eval, y_eval = eval_df.drop(columns=[target]), eval_df[target]

    params = {
        "n_estimators": 500,
        "learning_rate": 0.05,
        "max_depth": 6,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "random_state": random_state,
        "n_jobs": -1,
        "tree_method": "hist",
    }
    if model_params:
        params.update(model_params)

    logger.info(f"🏋️ Training XGBoost model with params: {params}")
    model = XGBRegressor(**params)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_eval)
    mae = float(mean_absolute_error(y_eval, y_pred))
    rmse = float(np.sqrt(mean_squared_error(y_eval, y_pred)))
    r2 = float(r2_score(y_eval, y_pred))
    metrics = {"mae": mae, "rmse": rmse, "r2": r2}

    logger.info(f"📊 Model Metrics: MAE={mae:.2f}, RMSE={rmse:.2f}, R²={r2:.4f}")

    # Save model locally
    out = Path(model_output)
    out.parent.mkdir(parents=True, exist_ok=True)
    dump(model, out)
    logger.info(f"💾 Model saved locally to {out}")

    # Upload to S3 if enabled
    if upload_to_s3_enabled:
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

        # Upload latest version
        s3_key_latest = f"models/production/xgb_model_latest.pkl"
        upload_to_s3(out, s3_key_latest)

        # Upload versioned copy
        s3_key_versioned = f"models/versions/xgb_model_{timestamp}.pkl"
        upload_to_s3(out, s3_key_versioned)

        # Upload encoders if they exist
        freq_encoder_path = out.parent / "freq_encoder.pkl"
        target_encoder_path = out.parent / "target_encoder.pkl"

        if freq_encoder_path.exists():
            upload_to_s3(freq_encoder_path, f"models/production/freq_encoder_latest.pkl")
            upload_to_s3(freq_encoder_path, f"models/versions/freq_encoder_{timestamp}.pkl")

        if target_encoder_path.exists():
            upload_to_s3(target_encoder_path, f"models/production/target_encoder_latest.pkl")
            upload_to_s3(target_encoder_path, f"models/versions/target_encoder_{timestamp}.pkl")

        logger.info(f"☁️ Models and artifacts uploaded to S3")

    logger.info("✅ Training pipeline completed successfully!")

    return model, metrics


if __name__ == "__main__":
    train_model()
