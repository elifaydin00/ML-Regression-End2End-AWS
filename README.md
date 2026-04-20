# Housing Regression ML — End-to-End MLOps Pipeline

> Production-ready ML pipeline for housing price prediction. XGBoost model trained on Redfin market data, served via FastAPI on AWS EC2 Free Tier, with automated monthly retraining and GitHub Actions CI/CD.

---

## Architecture

![Architecture Diagram](architecture.png)
<img width="7280" height="4240" alt="image" src="https://github.com/user-attachments/assets/2e4b026b-24a1-449a-b55e-180495bdbdc2" />

```
┌──────────────────────────────────────────────────────────────┐
│  git push → GitHub Actions → (1) build image → push to ECR  │
│                            → (2) SSM → EC2 (auto-deploy)    │
└──────────────────────────────────────────────────────────────┘

EventBridge (monthly) → Lambda → ephemeral EC2 (t2.small)
  → docker pull ECR image → docker run training → s3 cp models → shutdown

EC2 t2.micro :8000 (API)  ←→  S3 (models + data)  ←→  CloudWatch (logs)
ECR: housing-ml-training (versioned Docker training images)
```

### Deployment Paths

| Component | Runtime | How Deployed |
|-----------|---------|-------------|
| Training pipeline | Docker container on ephemeral EC2 (t2.small) | Lambda → `ec2.run_instances` → pulls ECR image, self-terminates after training |
| FastAPI API | Bare Python (uv) + systemd on persistent EC2 (t2.micro) | GitHub Actions → SSM → `scripts/deploy_ec2.sh` (git pull + uv sync + restart) |

**Live API:** `http://44.219.159.59:8000`

---

## Project Structure

```
├── src/
│   ├── feature_pipeline/
│   │   ├── load.py                  # Time-based data split (train/eval/holdout)
│   │   ├── preprocess.py            # Clean, normalise, deduplicate
│   │   └── feature_engineering.py  # Date features, freq/target encoding
│   ├── training_pipeline/
│   │   ├── train.py                 # XGBoost training + S3 upload
│   │   ├── tune.py                  # Optuna hyperparameter search + MLflow
│   │   └── eval.py                  # MAE, RMSE, R², feature importance
│   ├── inference_pipeline/
│   │   └── inference.py             # Applies saved encoders + model predict
│   ├── api/
│   │   └── main.py                  # FastAPI: /health, /predict, /run_batch
│   ├── batch/
│   │   └── run_monthly.py           # Batch predictions on holdout data
│   └── data/
│       └── upload_to_s3.py          # Sync local models/data to S3
├── Dockerfile                       # Training image (python:3.11-slim + AWS CLI + uv)
├── train_entrypoint.sh              # Container entrypoint: pipeline stages + S3 upload + API restart
├── terraform/
│   ├── main.tf                      # All AWS resources (EC2, S3, ECR, Lambda, IAM…)
│   ├── user_data.sh                 # EC2 (API) boot script
│   ├── lambda_trigger.py            # Monthly training trigger — launches ephemeral EC2 with Docker
│   └── build_zip.py                 # Package Lambda for deployment (cross-platform)
├── tests/
│   ├── test_features.py
│   ├── test_training.py
│   ├── test_inference.py
│   └── data_quality.py
├── configs/
│   ├── app_config.yml
│   ├── mlflow_config.yml
│   └── ge_expectations.yml
├── scripts/
│   ├── deploy_ec2.sh                # EC2 deploy script (sent base64-encoded via SSM)
│   └── verify_aws_setup.py
├── .github/workflows/deploy.yml     # CI/CD: push to main → deploy to EC2
├── pyproject.toml
└── uv.lock
```

---

## Local Development

### Setup

```powershell
git clone https://github.com/elifaydin00/ML-Regression-End2End-AWS.git
cd ML-Regression-End2End-AWS
uv sync
```

### Run the ML Pipeline

```powershell
# 1. Load and split data
uv run python src/feature_pipeline/load.py

# 2. Preprocess
uv run python src/feature_pipeline/preprocess.py

# 3. Feature engineering (saves encoders to models/)
uv run python src/feature_pipeline/feature_engineering.py

# 4. Hyperparameter tuning with Optuna + MLflow
#    Runs 15 trials, finds best params, retrains final model
#    Saves best model to models/xgb_best_model.pkl
uv run python src/training_pipeline/tune.py

# 5. Evaluate on holdout set
uv run python src/training_pipeline/eval.py
```

### View MLflow Experiment Results

After running `tune.py`, view all trials and compare metrics in the MLflow UI:

```powershell
.\.venv\Scripts\mlflow.exe ui --backend-store-uri sqlite:///mlflow.db --workers 1
# Open http://127.0.0.1:5000
```

You will see:
- All 15 Optuna trials as nested runs under experiment `xgboost_optuna_housing`
- Metrics per trial: RMSE, MAE, R²
- Best model run (`best_xgb_model`) with winning hyperparameters logged

### Run the API Locally

```powershell
$env:USE_S3 = "false"
uv run uvicorn src.api.main:app --host 0.0.0.0 --port 8000 --reload
```

Test it:
```powershell
Invoke-RestMethod http://localhost:8000/health

$body = '[{"bedrooms":3,"bathrooms":2,"sqft_living":1500,"zipcode":98001,"date":"2024-01-15","city_full":"Auburn"}]'
Invoke-RestMethod -Uri http://localhost:8000/predict -Method Post -Body $body -ContentType "application/json"
```

### Run Tests

```powershell
uv run pytest tests/ -v
```

---

## AWS Deployment

### Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.0 installed
- SSH key pair created (`housing-ml-key` in us-east-1)
- GitHub repo with secrets configured (see CI/CD section)

### 1. Upload data and models to S3

```powershell
$env:USE_S3 = "true"
$env:S3_BUCKET = "house-forecast"
$env:AWS_REGION = "us-east-1"
uv run python src/data/upload_to_s3.py
```

### 2. Build Lambda package

```powershell
cd terraform
uv run python build_zip.py
cd ..
```

### 3. Deploy infrastructure with Terraform

```powershell
cd terraform
terraform init
terraform apply -var="github_repo_url=https://github.com/elifaydin00/ML-Regression-End2End-AWS.git"
cd ..
```

This creates: EC2 t2.micro, S3 bucket, Elastic IP, Lambda function, EventBridge rule, CloudWatch log group, IAM roles, Security group.

### 4. EC2 manual setup (first time only)

The `user_data.sh` script runs on boot. If it partially fails (check `/var/log/cloud-init-output.log`), SSH in and complete setup:

```bash
ssh -i ~/.ssh/housing-ml-key.pem ec2-user@44.219.159.59

# Install SSM agent (required for CI/CD)
sudo dnf install -y amazon-ssm-agent
sudo systemctl enable --now amazon-ssm-agent

# Clone repo and set up environment
cd /opt/housing-ml
git clone https://github.com/elifaydin00/ML-Regression-End2End-AWS.git app
cd app
curl -LsSf https://astral.sh/uv/install.sh | sh
~/.local/bin/uv sync
```

### 5. Verify deployment

```powershell
Invoke-RestMethod http://44.219.159.59:8000/health
```

---

## CI/CD — Automatic Deployment

Every push to `main` triggers two GitHub Actions jobs:

1. **`build-and-push`** — builds Docker training image, pushes to ECR as `:latest` and `:<git-sha>`
2. **`deploy`** — starts API EC2 if stopped, waits for SSM, runs `scripts/deploy_ec2.sh` via SSM

**Required GitHub Secrets:**

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | GitHub Actions IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | GitHub Actions IAM user secret key |
| `EC2_INSTANCE_ID` | API EC2 instance ID (`i-xxxxx`) |
| `GH_PAT` | GitHub Personal Access Token (for EC2 to pull code) |

**GitHub Actions IAM user needs these permissions:**
```json
{
  "Action": [
    "ec2:DescribeInstances", "ec2:StartInstances",
    "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
    "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload",
    "ecr:PutImage", "ecr:UploadLayerPart",
    "ssm:DescribeInstanceInformation", "ssm:SendCommand",
    "ssm:GetCommandInvocation", "sts:GetCallerIdentity"
  ]
}
```

**Deploy flow:**
```
push to main → build Docker image → push to ECR
             → start EC2 if stopped → wait for SSM → deploy_ec2.sh (git pull + uv sync + restart)
```

---

## Automated Monthly Retraining

EventBridge fires on the 1st of every month at 2 AM UTC → Lambda → fresh ephemeral EC2 (t2.small):

```
Lambda: ec2.run_instances → ephemeral EC2 boots with user_data:
  → dnf install docker + amazon-ssm-agent
  → aws ecr get-login-password | docker login
  → docker pull <ecr_image>:latest
  → docker run (training container):
      load data from S3 → preprocess → feature engineering
      → tune.py (15 Optuna trials, MLflow tracking)
      → best params → model retrained → xgb_best_model.pkl
      → aws s3 cp models to s3://house-forecast/models/production/
      → aws ssm send-command: systemctl restart housing-ml-api
  → shutdown -h now (instance terminates)

API EC2: startup downloads fresh model from S3 → /predict serves new model
```

**S3 layout after each monthly run:**
```
s3://house-forecast/
├── models/
│   ├── production/
│   │   └── xgb_model_latest.pkl        ← overwritten (API reads this)
│   └── versions/
│       └── YYYY-MM/                    ← archived for rollback
│           └── xgb_best_model.pkl
└── mlflow/
    └── artifacts/xgboost_optuna_housing/
        └── <run_id>/model/             ← each trial's serialised model
```

**Trigger manually:**
```powershell
aws lambda invoke --function-name housing-trigger-training-production --region us-east-1 response.json
Get-Content response.json
```

**Watch training logs:**
```powershell
aws logs tail /ec2/housing-ml --follow --region us-east-1
```

---

## Monitoring

```powershell
# Live API logs
aws logs tail /ec2/housing-ml --follow --region us-east-1

# Lambda logs (monthly training trigger)
aws logs tail /aws/lambda/housing-trigger-training-production --follow --region us-east-1

# SSH and check systemd service
ssh -i ~/.ssh/housing-ml-key.pem ec2-user@44.219.159.59
sudo systemctl status housing-ml-api
sudo journalctl -u housing-ml-api -f
```

---

## Cost

| Service | Usage | Cost (free tier) | Cost (after 12 months) |
|---------|-------|-----------------|----------------------|
| EC2 t2.micro (API) | 720 hrs/month | $0 | ~$8/month |
| EC2 t2.small (training) | ~0.5 hrs/month | $0 | ~$0.01/month |
| ECR | ~1-2 GB image | $0 | ~$0.10/month |
| S3 | ~500 MB | $0 | ~$0.01/month |
| Lambda | 1/month | $0 | $0 |
| EventBridge | 1 rule | $0 | $0 |
| CloudWatch | ~1 GB logs | $0 | ~$0.50/month |
| Elastic IP | Attached | $0 | $0 |
| **Total** | | **$0** | **~$8-10/month** |

---

## Key Design Decisions

**API on EC2 + systemd; Training in Docker on ephemeral EC2** — The API runs on a persistent t2.micro (free tier). Training runs inside a Docker container on a fresh ephemeral t2.small that self-terminates — reproducible environment, no dependency drift, isolated from the API.

**Time-based data splits** — Prevents data leakage. Housing prices are time-dependent; random splits would make the model look better than it actually is.

**SSM for remote management** — No open SSH port, no key rotation, full IAM control, automatic CloudWatch logging of every command.

**S3 for model storage** — Models persist independently of EC2 lifecycle. Any service can access them. Built-in versioning.

**Optuna + MLflow for hyperparameter tuning** — Optuna explores 9-dimensional hyperparameter space over 15 trials, minimising RMSE. Every trial is logged to MLflow (SQLite backend locally, S3 artifacts on EC2). The best parameters are used to retrain the final model — this tuned model is what serves production inference, not a baseline with hardcoded defaults.

**MLflow with SQLite** — No separate MLflow server needed. Experiment tracking stored in `mlflow.db` locally and `/tmp/mlflow.db` on EC2, artifacts in S3. View results with `mlflow ui --backend-store-uri sqlite:///mlflow.db --workers 1`.

---

## Further Reading

See `BLOG.md` for a detailed explanation of every component, every AWS service, and lessons learned — written as a Medium article for people learning MLOps.
