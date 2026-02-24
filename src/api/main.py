# Goal: Create a FastAPI app to serve your trained ML model into a web service that anyone
# (or any system) can call over HTTP.

import logging
from fastapi import FastAPI            # Web framework for APIs
from pathlib import Path               # For handling file paths cleanly
from typing import List, Dict, Any, Optional     # For type hints (clarity in endpoints)
import pandas as pd                    # To handle incoming JSON as DataFrames
import boto3, os                       # AWS SDK for Python + env variables
from pydantic import BaseModel         # Input validation

# Import inference pipeline
from src.inference_pipeline.inference import predict

logger = logging.getLogger(__name__)

# ----------------------------
# Config
# ----------------------------
S3_BUCKET = os.getenv("S3_BUCKET", "house-forecast")
REGION = os.getenv("AWS_REGION")  # reads from ~/.aws/config when not set
s3 = boto3.client("s3", region_name=REGION)

# Ensures your app always has the latest model/data locally,
# but avoids re-downloading every time it starts.
def load_from_s3(key, local_path):
    """Download from S3 if not already cached locally."""
    local_path = Path(local_path)
    if not local_path.exists():
        os.makedirs(local_path.parent, exist_ok=True)
        logger.info("Downloading %s from S3...", key)
        s3.download_file(S3_BUCKET, key, str(local_path))
    return str(local_path)

# ----------------------------
# Paths (resolved at startup)
# ----------------------------
MODEL_PATH = Path("models/xgb_best_model.pkl")
TRAIN_FE_PATH = Path("data/processed/feature_engineered_train.csv")
TRAIN_FEATURE_COLUMNS: Optional[List[str]] = None

# ----------------------------
# Pydantic input model
# ----------------------------
class HousingRecord(BaseModel):
    model_config = {"extra": "allow"}

    bedrooms: Optional[float] = None
    bathrooms: Optional[float] = None
    sqft_living: Optional[float] = None
    sqft_lot: Optional[float] = None
    floors: Optional[float] = None
    waterfront: Optional[float] = None
    view: Optional[float] = None
    condition: Optional[float] = None
    sqft_above: Optional[float] = None
    sqft_basement: Optional[float] = None
    yr_built: Optional[float] = None
    yr_renovated: Optional[float] = None
    zipcode: Optional[float] = None
    lat: Optional[float] = None
    long: Optional[float] = None
    sqft_living15: Optional[float] = None
    sqft_lot15: Optional[float] = None
    date: Optional[str] = None
    city_full: Optional[str] = None

# ----------------------------
# App
# ----------------------------
# Instantiates the FastAPI app.
app = FastAPI(title="Housing Regression API")

@app.on_event("startup")
async def load_artifacts():
    """Download model and feature schema from S3 at startup (non-fatal if S3 unavailable)."""
    global TRAIN_FEATURE_COLUMNS
    try:
        load_from_s3("models/production/xgb_model_latest.pkl", str(MODEL_PATH))
        load_from_s3("processed/feature_engineered_train.csv", str(TRAIN_FE_PATH))
        logger.info("Artifacts loaded successfully from S3.")
    except Exception as exc:
        logger.warning("Could not download artifacts from S3 (will use local cache if available): %s", exc)

    if TRAIN_FE_PATH.exists():
        _train_cols = pd.read_csv(TRAIN_FE_PATH, nrows=1)
        TRAIN_FEATURE_COLUMNS = [c for c in _train_cols.columns if c != "price"]

# / → simple landing endpoint to confirm API is alive.
@app.get("/")
def root():
    return {"message": "Housing Regression API is running"}

# /health → checks if model exists, returns status info (like expected feature count).
@app.get("/health")
def health():
    status: Dict[str, Any] = {"model_path": str(MODEL_PATH)}
    if not MODEL_PATH.exists():
        status["status"] = "unhealthy"
        status["error"] = "Model not found"
    else:
        status["status"] = "healthy"
        if TRAIN_FEATURE_COLUMNS:
            status["n_features_expected"] = len(TRAIN_FEATURE_COLUMNS)
    return status

# Prediction Endpoint: This is the core ML serving endpoint.
@app.post("/predict")
def predict_batch(data: List[HousingRecord]):
    if not MODEL_PATH.exists():
        return {"error": f"Model not found at {str(MODEL_PATH)}"}

    df = pd.DataFrame([record.model_dump(exclude_none=True) for record in data])
    if df.empty:
        return {"error": "No data provided"}

    preds_df = predict(df, model_path=MODEL_PATH)

    resp = {"predictions": preds_df["predicted_price"].astype(float).tolist()}
    if "actual_price" in preds_df.columns:
        resp["actuals"] = preds_df["actual_price"].astype(float).tolist()

    return resp

# Batch runner
from src.batch.run_monthly import run_monthly_predictions

# Trigger a monthly batch job via API.
@app.post("/run_batch")
def run_batch():
    preds = run_monthly_predictions()
    return {
        "status": "success",
        "rows_predicted": int(len(preds)),
        "output_dir": "data/predictions/"
    }

# Returns a preview of the most recent batch predictions.
@app.get("/latest_predictions")
def latest_predictions(limit: int = 5):
    pred_dir = Path("data/predictions")
    files = sorted(pred_dir.glob("preds_*.csv"))
    if not files:
        return {"error": "No predictions found"}

    latest_file = files[-1]
    df = pd.read_csv(latest_file)
    return {
        "file": latest_file.name,
        "rows": int(len(df)),
        "preview": df.head(limit).to_dict(orient="records")
    }


"""
Execution Order / Module Flow

1. Imports (FastAPI, pandas, boto3, your inference function).
2. Config setup (env vars -> bucket/region).
3. S3 utility (load_from_s3).
4. App creation (app = FastAPI).
5. Startup event: download model/artifacts from S3 with try/except.
6. Declare endpoints (/, /health, /predict, /run_batch, /latest_predictions).
"""
