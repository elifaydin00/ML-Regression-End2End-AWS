# CLAUDE.md — Project Context for AI Assistants

> This file provides context about the Housing Regression ML project for Claude Code and other AI assistants.

---

## Project Summary

**Name**: Housing Regression ML — End-to-End MLOps Pipeline
**Data**: Redfin housing market data (`HouseTS.csv`) — monthly median sale prices by zip code across the US
**Model**: XGBoost regression, predicts median market sale price per zip code
**Stack**: Python 3.11, XGBoost, FastAPI, Pydantic v2, MLflow (SQLite), Optuna, uv
**Deployment**: API on EC2 t2.micro + systemd; Training in Docker container on ephemeral EC2 (ECR image)
**Infrastructure**: Terraform (EC2, S3, ECR, Lambda, EventBridge, IAM, CloudWatch, Elastic IP)
**CI/CD**: GitHub Actions — builds Docker image → pushes to ECR → deploys API to EC2 via SSM
**Status**: Fully deployed and operational

---

## Live Infrastructure

| Resource | Value |
|----------|------|
| EC2 Instance | `i-0be34b1d7f2933e29` |
| EC2 Public IP | `44.219.159.59` (Elastic IP — permanent) |
| API URL | `http://44.219.159.59:8000` |
| S3 Bucket | `house-forecast` |
| AWS Region | `us-east-1` |
| GitHub Repo | `https://github.com/elifaydin00/ML-Regression-End2End-AWS.git` |
| EC2 app path | `/opt/housing-ml/app` |
| EC2 systemd service | `housing-ml-api.service` |

---

## Architecture

```
git push → GitHub Actions → (1) build Docker image → push to ECR
                          → (2) SSM → EC2 (deploy API code + restart service)

EventBridge (1st of month, 2AM UTC) → Lambda → ec2.run_instances (ephemeral t2.small)
  → ephemeral EC2 boots → docker pull ECR image → docker run training container
  → container: load → preprocess → feature_eng → tune (15 Optuna trials, MLflow)
  → aws s3 cp models → SSM restart API EC2 → ephemeral EC2 terminates

User → POST /predict → FastAPI (EC2:8000) → inference.py → XGBoost → prediction

API EC2 ←→ S3 (house-forecast): read model on startup (always fresh from S3)
ECR repo: housing-ml-training (stores versioned Docker training images)
CloudWatch /ec2/housing-ml: API logs (stream: api) + training container logs (stream: training-container)
```

---

## File Structure

```
src/
├── feature_pipeline/
│   ├── load.py                  # Download HouseTS.csv, time-split into train/eval/holdout
│   ├── preprocess.py            # clean_and_merge(), drop_duplicates(), remove_outliers()
│   └── feature_engineering.py  # Date features, frequency encoding (zipcode), target encoding (city_full)
├── training_pipeline/
│   ├── train.py                 # XGBoost fit, saves xgb_model.pkl, uploads to S3 if USE_S3=true
│   ├── tune.py                  # Optuna trials, MLflow tracking (SQLite), saves xgb_best_model.pkl
│   └── eval.py                  # MAE, RMSE, R² on holdout set, feature importance plots
├── inference_pipeline/
│   └── inference.py             # predict(): preprocess → encode → align → model.predict()
├── api/
│   └── main.py                  # FastAPI: /health, /predict, /run_batch, /latest_predictions
├── batch/
│   └── run_monthly.py           # Batch predict on raw holdout.csv (NOT cleaning_holdout.csv)
└── data/
    └── upload_to_s3.py          # Sync models/ and data/ to S3

Dockerfile                       # Training image: python:3.11-slim + AWS CLI + uv; ENTRYPOINT train_entrypoint.sh
train_entrypoint.sh              # Container entrypoint: runs all 4 pipeline stages + S3 upload + SSM API restart

terraform/
├── main.tf                      # All AWS resources (EC2, S3, ECR, Lambda, IAM, EventBridge, CloudWatch, SG)
├── user_data.sh                 # EC2 (API) init script (templatefile with s3_bucket, aws_region, etc.)
├── lambda_trigger.py            # Lambda handler: ec2.run_instances ephemeral training EC2 with Docker user_data
├── build_zip.py                 # Rebuild lambda_trigger.zip (Python, works on Windows without zip CLI)
├── lambda_trigger.zip           # Zipped Lambda deployment package (index.py = lambda_trigger.py)
├── terraform.tfstate            # CRITICAL — never delete, tracks created resources
└── terraform.tfvars             # Variable values (git-ignored)

scripts/
├── deploy_ec2.sh                # Bootstrap-aware EC2 deploy script (sent via SSM, base64-encoded)
└── verify_aws_setup.py          # Checks AWS credentials, S3, EC2 access

tests/
├── test_features.py
├── test_training.py
├── test_inference.py
└── data_quality.py              # Great Expectations schema checks

.github/workflows/
└── deploy.yml                   # CI/CD: push to main → EC2 deploy via SSM

configs/
├── app_config.yml
├── mlflow_config.yml
└── ge_expectations.yml

```

---

## Key Implementation Details

### Inference Pipeline (`src/inference_pipeline/inference.py`)

- `predict()` takes **raw** input (same schema as `holdout.csv` from `load.py`)
- Internally calls `clean_and_merge()`, `drop_duplicates()`, `remove_outliers()` — do NOT pass already-preprocessed data
- Loads freq_encoder and target_encoder from `.pkl` files and calls `.transform()` (never `.fit_transform()`)
- After loading model: `df = df.reindex(columns=model.get_booster().feature_names, fill_value=0)` — aligns columns exactly
- Model fallback: tries `xgb_best_model.pkl` first, falls back to `xgb_model.pkl` if not found

### API (`src/api/main.py`)

- S3 model download happens in `@app.on_event("startup")` with try/except — app still starts if S3 unavailable
- Input validation via `HousingRecord` Pydantic model with `model_config = {"extra": "allow"}`
- DataFrame creation: `pd.DataFrame([record.model_dump(exclude_none=True) for record in data])` — `exclude_none=True` is critical to avoid object-typed None columns
- S3 key for model: `"models/production/xgb_model_latest.pkl"` → saved locally as `"models/xgb_best_model.pkl"`

### Batch Pipeline (`src/batch/run_monthly.py`)

- Input: `data/raw/holdout.csv` (raw data from `load.py`) — NOT `data/processed/cleaning_holdout.csv`
- `predict()` handles preprocessing internally

### Docker Training Image (`Dockerfile` + `train_entrypoint.sh`)

- Base: `python:3.11-slim` + AWS CLI v2 + uv
- `ENV PYTHONUNBUFFERED=1` — required for real-time CloudWatch log streaming
- `ENV PYTHONPATH=/app`
- Entrypoint: `train_entrypoint.sh` runs all 4 stages + `aws s3 cp` models + SSM restart to API EC2
- Built by GitHub Actions on every push to `main`, tagged `:latest` and `:<git-sha>`, pushed to ECR

### Lambda (`terraform/lambda_trigger.py`)

- Uses `ec2.run_instances()` — launches fresh ephemeral t2.small EC2, NOT SSM to persistent EC2
- user_data: installs Docker + SSM agent, pulls ECR image, runs container, self-terminates via `shutdown -h now`
- Boot log captured to file, uploaded to `s3://house-forecast/logs/` via `trap EXIT` for debugging
- Container logs streamed to CloudWatch via `--log-driver=awslogs`
- `InstanceInitiatedShutdownBehavior='terminate'` — EC2 disappears from console after training
- `BlockDeviceMappings`: 20GB gp3 (default 8GB is too small for Docker + image)
- Rebuild zip: `cd terraform && uv run python build_zip.py`
- Lambda environment: `S3_BUCKET`, `ECR_IMAGE_URI`, `INSTANCE_PROFILE_NAME`, `SECURITY_GROUP_ID`, `SUBNET_ID`, `AMI_ID`, `API_INSTANCE_ID`
- Does NOT set `AWS_REGION` (reserved by Lambda runtime)

### Terraform (`terraform/main.tf`)

- API EC2 has `iam_instance_profile` with `AmazonSSMManagedInstanceCore` + S3 + CloudWatch + ECR pull + SSM SendCommand
- Lambda IAM policy: `ec2:RunInstances`, `ec2:CreateTags`, `iam:PassRole` (EC2 role ARN), CloudWatch logs
- ECR repo: `aws_ecr_repository "training"` → `housing-ml-training`
- `source_code_hash = filebase64sha256(...)` on Lambda resource — forces Lambda update when zip changes
- `github_repo_url` is a required variable (no default)

### EC2 Setup (API — persistent)

- App location: `/opt/housing-ml/app/`
- API script: `/opt/housing-ml/run_api.sh`
- systemd service: `/etc/systemd/system/housing-ml-api.service`
- Python via uv: `/home/ec2-user/.local/bin/uv`
- venv: `/opt/housing-ml/app/.venv/`
- Bootstrap + deploy handled by `scripts/deploy_ec2.sh` (sent via SSM, base64-encoded)

### CI/CD (`.github/workflows/deploy.yml`)

- **Job 1 `build-and-push`**: checkout → configure AWS → login to ECR → docker build → tag + push `:latest` and `:<git-sha>`
- **Job 2 `deploy`** (needs `build-and-push`): start EC2 if stopped → wait SSM online → send `scripts/deploy_ec2.sh` base64-encoded via SSM
- `deploy_ec2.sh`: detects fresh EC2 (no `.git` dir) → clone + full bootstrap; else `sudo -u ec2-user git pull` + `uv sync` + `systemctl restart`
- All git commands run as `ec2-user` (directory owned by ec2-user, SSM runs as root — must `sudo -u ec2-user`)

---

## AWS Resources (Terraform-managed)

| Resource | Name | Purpose |
|----------|------|---------|
| EC2 Instance (persistent) | Housing ML Instance | Runs FastAPI API 24/7 |
| EC2 Instance (ephemeral) | housing-ml-training-ephemeral | Launched by Lambda for training, self-terminates |
| ECR Repository | housing-ml-training | Stores versioned Docker training images |
| IAM Role | housing-ec2-ml-role-production | EC2 identity (S3 + SSM + CloudWatch + ECR pull + SSM SendCommand) |
| IAM Instance Profile | housing-ec2-ml-profile-production | Attaches role to both persistent and ephemeral EC2 |
| S3 Bucket | house-forecast | Model + data + logs storage |
| Lambda Function | housing-trigger-training-production | Monthly training trigger (launches ephemeral EC2) |
| IAM Role | housing-lambda-training-role-production | Lambda identity (ec2:RunInstances + iam:PassRole) |
| EventBridge Rule | housing-training-schedule-production | Cron: 1st of month 2AM UTC |
| CloudWatch Log Group | /ec2/housing-ml | API logs (stream: api) + training container logs (stream: training-container) |
| Security Group | housing-ml-ec2-sg-production | Ports 22, 80, 8000 open (shared by API + ephemeral EC2) |
| Elastic IP | (attached to API EC2) | Static IP: 44.219.159.59 |
| Key Pair | housing-ml-key | SSH access |

---

## Environment Variables

| Variable | Where Used | Value |
|----------|-----------|-------|
| `USE_S3` | train.py, api startup | `"true"` on EC2, `"false"` locally |
| `S3_BUCKET` | train.py, api startup | `"house-forecast"` |
| `AWS_REGION` | boto3 clients | `"us-east-1"` (or from `~/.aws/config`) |
| `PYTHONPATH` | EC2 systemd service | `/opt/housing-ml/app` |
| `MLFLOW_TRACKING_URI` | tune.py | `sqlite:////tmp/mlflow.db` on EC2 |
| `MLFLOW_ARTIFACT_ROOT` | tune.py | `s3://house-forecast/mlflow/artifacts` |

---

## What Was Removed (and Why)

| Removed | Reason |
|---------|--------|
| `Dockerfile.train`, `Dockerfile.streamlit` | Replaced by single `Dockerfile` (training image only) |
| `housing-api-task-def.json`, `training-task-def.json` | ECS task definitions, deployment path not used |
| `scripts/deploy_to_ec2.ps1`, `deploy_to_ec2.sh` | Replaced by GitHub Actions + `scripts/deploy_ec2.sh` via SSM |
| `scripts/build_and_push.sh` | Replaced by GitHub Actions `build-and-push` job |
| `scripts/download_models.sh` | Not used |
| `scripts/quickstart.sh` | Outdated |
| `scripts/setup_aws_credentials.ps1`, `setup_s3_integration.ps1` | One-time setup scripts, already done |
| `terraform/build_lambda.ps1`, `build_lambda.sh` | Replaced by `terraform/build_zip.py` (cross-platform) |
| `app.py` | Streamlit UI, not relevant to AI Engineering focus |
| `src/housing_regression_mle.egg-info/` | Auto-generated by pip install -e |
| `s3://house-forecast/models/production/xgb_best_model_latest.pkl` | Old naming convention, replaced by `xgb_model_latest.pkl` |

---

## Common Operations

```powershell
# Check API health
Invoke-RestMethod http://44.219.159.59:8000/health

# Trigger training manually (Lambda → ephemeral EC2 → Docker)
aws lambda invoke --function-name housing-trigger-training-production response.json

# View live logs (includes training-container stream when training runs)
aws logs tail /ec2/housing-ml --follow --region us-east-1

# Verify models in S3 after training
aws s3 ls s3://house-forecast/models/production/

# Rebuild Lambda zip after changing lambda_trigger.py
cd terraform && uv run python build_zip.py && cd ..
# Then: terraform apply -target="aws_lambda_function.trigger_training"

# SSH into API EC2
ssh -i ~/.ssh/housing-ml-key.pem ec2-user@44.219.159.59

# Check systemd service on EC2
sudo systemctl status housing-ml-api
sudo journalctl -u housing-ml-api -f

# Deploy code (push to GitHub → Actions builds Docker image + deploys API)
git push origin main
```

---

## Known Gotchas

1. **`exclude_none=True`** in `model_dump()` is required — otherwise None-valued fields create object-dtype columns that XGBoost rejects
2. **`df.reindex(columns=model.get_booster().feature_names)`** is required — column alignment between training schema and inference input
3. **SSM agent** must be running on API EC2 (`sudo systemctl status amazon-ssm-agent`) for CI/CD to work
4. **`AWS_REGION` is reserved** in Lambda — do not set it in Terraform Lambda environment block
5. **`terraform.tfstate`** must never be deleted — it tracks all created resources
6. **EC2 runs independently** of your laptop — closing PyCharm does not stop the API
7. **Free tier:** API EC2 ~720 hrs/month + ephemeral training EC2 ~0.5 hrs/month = 720.5 hrs (under 750 hr limit)
8. **`PYTHONUNBUFFERED=1`** must be set in Dockerfile — without it, Python buffers stdout and CloudWatch shows no logs until container exits
9. **Ephemeral EC2 disk size**: default 8GB is too small (Docker + image + data). Always use 20GB gp3 via `BlockDeviceMappings`
10. **Ephemeral EC2 instance type**: t2.micro (1GB RAM) causes MemoryError on large DataFrames. Use t2.small (2GB)
11. **Git dubious ownership**: SSM runs as root but `/opt/housing-ml/app` is owned by ec2-user — always `sudo -u ec2-user git` for git commands
12. **Lambda zip must be rebuilt** after changing `lambda_trigger.py`: run `build_zip.py`, then `terraform apply -target="aws_lambda_function.trigger_training"`
13. **`source_code_hash`** on Lambda resource is required — without it, Terraform won't update Lambda even when the zip changes
14. **S3 streaming**: use `pd.read_csv(response['Body'])` directly — the StringIO double-read approach causes MemoryError on large CSVs in memory-constrained containers
