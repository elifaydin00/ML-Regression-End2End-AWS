# CLAUDE.md — Project Context for AI Assistants

> This file provides context about the Housing Regression ML project for Claude Code and other AI assistants.

---

## Project Summary

**Name**: Housing Regression ML — End-to-End MLOps Pipeline
**Data**: Redfin housing market data (`HouseTS.csv`) — monthly median sale prices by zip code across the US
**Model**: XGBoost regression, predicts median market sale price per zip code
**Stack**: Python 3.11, XGBoost, FastAPI, Pydantic v2, MLflow (SQLite), Optuna, uv
**Deployment**: AWS EC2 t2.micro + systemd (NOT Docker/ECS/Fargate)
**Infrastructure**: Terraform (EC2, S3, Lambda, EventBridge, IAM, CloudWatch, Elastic IP)
**CI/CD**: GitHub Actions + AWS SSM (push to main → auto-deploy to EC2)
**Status**: Fully deployed and operational

---

## Live Infrastructure

| Resource | Value |
|----------|-------|
| EC2 Instance | `i-05ac00076131b6a09` |
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
git push → GitHub Actions → AWS SSM → EC2 (deploy)

EventBridge (1st of month, 2AM UTC) → Lambda → SSM → EC2 (retrain)

User → POST /predict → FastAPI (EC2:8000) → inference.py → XGBoost → prediction

EC2 ←→ S3 (house-forecast): read model on startup, write new model after training
EC2 → CloudWatch (/ec2/housing-ml): API logs + training logs
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

terraform/
├── main.tf                      # All AWS resources
├── user_data.sh                 # EC2 init script (templatefile with s3_bucket, aws_region, etc.)
├── lambda_trigger.py            # Lambda handler: check EC2 → start if needed → SSM send-command
├── build_lambda.ps1             # Windows: zip lambda_trigger.py → lambda_trigger.zip
├── build_lambda.sh              # Linux/Mac equivalent
├── terraform.tfstate            # CRITICAL — never delete, tracks created resources
└── terraform.tfvars             # Variable values (git-ignored)

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

scripts/
└── verify_aws_setup.py          # Checks AWS credentials, S3, EC2 access
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

### Terraform (`terraform/main.tf`)

- EC2 has `iam_instance_profile` with `AmazonSSMManagedInstanceCore` + S3 access + CloudWatch logs
- Lambda IAM policy includes `ec2:StartInstances` (needed by `lambda_trigger.py`)
- `github_repo_url` is a required variable (no default)
- Lambda environment: does NOT set `AWS_REGION` (reserved by Lambda runtime)

### EC2 Setup

- App location: `/opt/housing-ml/app/`
- API script: `/opt/housing-ml/run_api.sh`
- Training script: `/opt/housing-ml/run_training.sh`
- systemd service: `/etc/systemd/system/housing-ml-api.service`
- Python via uv: `/home/ec2-user/.local/bin/uv`
- venv: `/opt/housing-ml/app/.venv/`

### CI/CD (`github/workflows/deploy.yml`)

- Triggers on push to `main`
- Uses `aws-actions/configure-aws-credentials@v4`
- Starts EC2 if stopped, waits for SSM agent ping = "Online"
- Deploy command via `AWS-RunShellScript`: git remote set-url (with GH_PAT), git pull, uv sync as ec2-user, systemctl restart
- SSM check does NOT use `2>/dev/null` so real errors are visible

---

## AWS Resources (Terraform-managed)

| Resource | Name | Purpose |
|----------|------|---------|
| EC2 Instance | Housing ML Instance | Runs FastAPI + training |
| IAM Role | housing-ec2-ml-role-production | EC2 identity (S3 + SSM + CloudWatch) |
| IAM Instance Profile | housing-ec2-ml-profile-production | Attaches role to EC2 |
| S3 Bucket | house-forecast | Model + data storage |
| Lambda Function | housing-trigger-training-production | Monthly training trigger |
| IAM Role | housing-lambda-training-role-production | Lambda identity |
| EventBridge Rule | housing-training-schedule-production | Cron: 1st of month 2AM UTC |
| CloudWatch Log Group | /ec2/housing-ml | API + training logs |
| Security Group | housing-ml-ec2-sg-production | Ports 22, 80, 8000 open |
| Elastic IP | (attached to EC2) | Static IP: 44.219.159.59 |
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
| `Dockerfile`, `Dockerfile.train`, `Dockerfile.streamlit` | Project uses EC2+systemd, not Docker/ECS |
| `housing-api-task-def.json`, `training-task-def.json` | ECS task definitions, deployment path not used |
| `scripts/deploy_to_ec2.ps1`, `deploy_to_ec2.sh` | Replaced by GitHub Actions CI/CD |
| `scripts/build_and_push.sh` | Docker/ECR script, not used |
| `scripts/download_models.sh` | Only referenced by Dockerfile (deleted) |
| `scripts/quickstart.sh` | Outdated, didn't reflect actual setup |
| `scripts/setup_aws_credentials.ps1`, `setup_s3_integration.ps1` | One-time setup scripts, already done |
| `app.py` | Streamlit UI, not relevant to AI Engineering focus |
| `src/housing_regression_mle.egg-info/` | Auto-generated by pip install -e |

---

## Common Operations

```powershell
# Check API health
Invoke-RestMethod http://44.219.159.59:8000/health

# Trigger training manually
aws lambda invoke --function-name housing-trigger-training-production response.json

# View live logs
aws logs tail /ec2/housing-ml --follow --region us-east-1

# SSH into EC2
ssh -i ~/.ssh/housing-ml-key.pem ec2-user@44.219.159.59

# Check systemd service on EC2
sudo systemctl status housing-ml-api
sudo journalctl -u housing-ml-api -f

# Deploy code (just push to GitHub)
git push origin main
```

---

## Next Steps — Levelling Up (Docker + Ephemeral EC2)

> Goal: mimic the GE Aerospace production pattern where Lambda spins up a fresh EC2,
> runs training inside a Docker container, uploads to S3, and terminates.
> Do these in order — each step is independently deployable and useful.

---

### Week 1 — Dockerise the Training Pipeline

**What to build:**
- Write a `Dockerfile` in the project root that containerises `tune.py`
- Confirm training runs identically inside the container as it does locally

**Files to create/change:**
- `Dockerfile` (new) — base image `python:3.11-slim`, copy code, install deps via `uv`, entrypoint runs `tune.py`
- Test locally: `docker build -t housing-ml-train . && docker run housing-ml-train`

**What you'll learn:**
- How Docker freezes an environment (why GE uses it for 1000+ parts)
- The difference between `COPY`, `RUN`, `CMD`, `ENTRYPOINT`
- Why `python:3.11-slim` not `python:3.11` (image size matters for pull time on EC2)

**Interview talking point:**
> "I containerised the training pipeline so the environment is identical every run —
> same Python version, same library versions, no dependency drift between months."

---

### Week 2 — Push Image to ECR

**What to build:**
- Create an ECR repository via Terraform (add to `terraform/main.tf`)
- Add a GitHub Actions job that builds and pushes the Docker image to ECR on push to main

**Files to change:**
- `terraform/main.tf` — add `aws_ecr_repository` resource
- `.github/workflows/deploy.yml` — add build + push step before the EC2 deploy step

**Commands to understand:**
```bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com
docker build -t housing-ml-train .
docker tag housing-ml-train:latest <account>.dkr.ecr.us-east-1.amazonaws.com/housing-ml-train:latest
docker push <account>.dkr.ecr.us-east-1.amazonaws.com/housing-ml-train:latest
```

**What you'll learn:**
- ECR is just a private Docker registry inside AWS — same as DockerHub but with IAM auth
- Why IAM role on EC2 allows pulling from ECR without credentials
- Image tagging strategy (`:latest` vs `:YYYY-MM` for versioning)

**Interview talking point:**
> "The training image lives in ECR. EC2 pulls it at runtime — the code and environment
> travel together as a single versioned artifact."

---

### Week 3 — Lambda Spins Up Ephemeral EC2

**What to build:**
- Rewrite `terraform/lambda_trigger.py` to launch a NEW EC2 instance instead of SSM to the existing one
- EC2 user_data: pull image from ECR, `docker run`, upload model to S3, `sudo shutdown`
- Existing API EC2 is untouched — training and serving are fully separated

**Key change in Lambda:**
```python
# Current (SSM to existing EC2):
ssm.send_command(InstanceIds=[existing_ec2_id], ...)

# New (spin up fresh EC2):
ec2.run_instances(
    ImageId="ami-...",           # Amazon Linux 2023
    InstanceType="t2.micro",
    IamInstanceProfile={"Name": "housing-ec2-ml-profile-production"},
    UserData="""#!/bin/bash
        aws ecr get-login-password --region us-east-1 | docker login ...
        docker pull <ecr_image>
        docker run -e USE_S3=true -e S3_BUCKET=house-forecast <ecr_image>
        sudo shutdown -h now
    """,
    MaxCount=1, MinCount=1
)
```

**Free tier note:** Training EC2 runs ~30 mins/month. API EC2 runs 720 hrs/month.
720 + 0.5 = 720.5 hrs — still under the 750 hr free tier limit.

**What you'll learn:**
- Ephemeral compute: EC2 as a job runner, not a server
- Why `shutdown -h now` inside user_data terminates the instance after training
- IAM instance profile allows EC2 to pull from ECR and write to S3 without credentials
- The exact pattern GE uses for monthly part cost forecasting

**Interview talking point:**
> "Lambda is a thin trigger — it computes the run date, builds S3 paths, and launches
> a fresh EC2. The EC2 pulls the training container from ECR, runs it, uploads the model
> to S3, and terminates. The API instance is completely separate and unaffected."

---

### After Week 3 — What You Can Confidently Say in Interviews

```
"My personal project mimics the production pattern I've seen in enterprise ML systems:

- EventBridge schedules a monthly Lambda trigger
- Lambda spins up an ephemeral EC2 (not a persistent server)
- EC2 pulls a Docker image from ECR — environment is frozen and reproducible
- Container runs hyperparameter tuning (Optuna, 15 trials, logged to MLflow)
- Best model retrained on full data, uploaded to S3
- EC2 terminates — no idle compute cost
- Separate persistent EC2 serves the FastAPI inference API
- CI/CD via GitHub Actions deploys code changes automatically

I built this to understand the infrastructure, not just the models."
```

---

## Known Gotchas

1. **`exclude_none=True`** in `model_dump()` is required — otherwise None-valued fields create object-dtype columns that XGBoost rejects
2. **`df.reindex(columns=model.get_booster().feature_names)`** is required — column alignment between training schema and inference input
3. **SSM agent** must be running on EC2 (`sudo systemctl status amazon-ssm-agent`) for CI/CD to work
4. **`AWS_REGION` is reserved** in Lambda — do not set it in Terraform Lambda environment block
5. **`terraform.tfstate`** must never be deleted — it tracks all created resources
6. **EC2 runs independently** of your laptop — closing PyCharm does not stop the API
7. **Free tier:** t2.micro gives 750 hrs/month = 24/7 coverage; no need to stop EC2 to stay free
