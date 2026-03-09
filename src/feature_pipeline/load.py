"""
Load & time-split the raw dataset.

- Production default writes to data/raw/
- Tests can pass a temp `output_dir` so nothing in data/ is touched.
- Supports loading from S3 bucket using AWS credentials
"""

import os
import pandas as pd
from pathlib import Path
import boto3

DATA_DIR = Path("data/raw")


def load_from_s3(bucket_name: str, file_key: str, region: str = None) -> pd.DataFrame:
    """
    Load CSV data from S3 bucket using your AWS credentials.

    Args:
        bucket_name: S3 bucket name (e.g., 'my-housing-data-bucket')
        file_key: S3 object key/path (e.g., 'raw/housing_data.csv')
        region: AWS region (default: from env var AWS_REGION or ~/.aws/config)

    Returns:
        DataFrame with loaded data

    Environment variables used:
        - AWS_ACCESS_KEY_ID: Your AWS access key
        - AWS_SECRET_ACCESS_KEY: Your AWS secret key
        - AWS_REGION: AWS region (optional, reads from ~/.aws/config if not set)
    """
    region = region or os.getenv('AWS_REGION')

    print(f"📥 Loading data from S3: s3://{bucket_name}/{file_key}")
    print(f"   Region: {region}")

    try:
        # Create S3 client - will use credentials from environment or ~/.aws/credentials
        s3_client = boto3.client('s3', region_name=region)

        # Stream directly into pandas — avoids loading the full file into memory twice
        response = s3_client.get_object(Bucket=bucket_name, Key=file_key)
        df = pd.read_csv(response['Body'])
        print(f"✅ Loaded {len(df)} rows from S3")

        return df

    except Exception as e:
        print(f"❌ Error loading from S3: {e}")
        print("\nMake sure:")
        print("1. AWS credentials are configured (run: aws configure)")
        print("2. Bucket name and file key are correct")
        print("3. Your IAM user has s3:GetObject permission")
        raise


def load_data_source() -> pd.DataFrame:
    """
    Load raw data from S3 or local file based on environment variables.

    Environment variables:
        USE_S3: Set to 'true' to load from S3 (default: 'false')
        S3_DATA_BUCKET: S3 bucket name (default: 'house-forecast')
        S3_DATA_KEY: S3 object key (default: 'raw/HouseTS.csv')
        LOCAL_DATA_PATH: Local file path (default: 'data/raw/HouseTS.csv')

    Returns:
        DataFrame with raw housing data
    """
    use_s3 = os.getenv('USE_S3', 'false').lower() == 'true'

    if use_s3:
        # Load from S3
        bucket = os.getenv('S3_DATA_BUCKET', 'house-forecast')
        key = os.getenv('S3_DATA_KEY', 'raw/HouseTS.csv')
        return load_from_s3(bucket, key)
    else:
        # Load from local file
        local_path = os.getenv('LOCAL_DATA_PATH', 'data/raw/HouseTS.csv')
        print(f"📂 Loading data from local file: {local_path}")
        df = pd.read_csv(local_path)
        print(f"✅ Loaded {len(df)} rows from local file")
        return df


def load_and_split_data(
    raw_path: str = None,  # Now optional, defaults to environment-based loading
    output_dir: Path | str = DATA_DIR,
):
    """
    Load raw dataset from S3 or local file, split into train/eval/holdout by date.

    Args:
        raw_path: (Optional) Explicit local file path. If None, uses load_data_source()
        output_dir: Directory to save split files

    Returns:
        Tuple of (train_df, eval_df, holdout_df)
    """
    # Load data
    if raw_path:
        print(f"📂 Loading data from specified path: {raw_path}")
        df = pd.read_csv(raw_path)
    else:
        # Use environment-based loading (S3 or local)
        df = load_data_source()

    # Ensure datetime + sort
    df["date"] = pd.to_datetime(df["date"])
    df = df.sort_values("date")

    # Cutoffs
    cutoff_date_eval = pd.Timestamp("2020-01-01")     # eval starts
    cutoff_date_holdout = pd.Timestamp("2022-01-01")  # holdout starts

    # Splits
    train_df = df[df["date"] < cutoff_date_eval]
    eval_df = df[(df["date"] >= cutoff_date_eval) & (df["date"] < cutoff_date_holdout)]
    holdout_df = df[df["date"] >= cutoff_date_holdout]

    # Save
    outdir = Path(output_dir)
    outdir.mkdir(parents=True, exist_ok=True)
    train_df.to_csv(outdir / "train.csv", index=False)
    eval_df.to_csv(outdir / "eval.csv", index=False)
    holdout_df.to_csv(outdir / "holdout.csv", index=False)

    print(f"✅ Data split completed (saved to {outdir}).")
    print(f"   Train: {train_df.shape}, Eval: {eval_df.shape}, Holdout: {holdout_df.shape}")

    return train_df, eval_df, holdout_df


if __name__ == "__main__":
    load_and_split_data()
