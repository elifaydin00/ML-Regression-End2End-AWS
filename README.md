# Housing Regression ML — End-to-End MLOps Pipeline

> Production-ready ML pipeline for housing price prediction. XGBoost model trained on Redfin market data, served via FastAPI on AWS EC2 Free Tier, with automated monthly retraining and GitHub Actions CI/CD.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  git push → GitHub Actions → SSM → EC2 (auto-deploy)        │
└──────────────────────────────────────────────────────────────┘

EventBridge (monthly) → Lambda → SSM → EC2 (auto-retrain)

EC2 t2.micro :8000  ←→  S3 (models + data)  ←→  CloudWatch (logs)
```

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
├── terraform/
│   ├── main.tf                      # All AWS resources (EC2, S3, Lambda, IAM…)
│   ├── user_data.sh                 # EC2 boot script
│   ├── lambda_trigger.py            # Monthly training trigger (Lambda function)
│   ├── build_lambda.ps1             # Package Lambda for deployment (Windows)
│   └── build_lambda.sh              # Package Lambda for deployment (Linux/Mac)
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

# 4. Train model (saves xgb_model.pkl to models/)
uv run python src/training_pipeline/train.py

# 5. Optional: hyperparameter tuning
uv run python src/training_pipeline/tune.py

# 6. Evaluate on holdout set
uv run python src/training_pipeline/eval.py
```

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
.\build_lambda.ps1
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

Every push to `main` automatically deploys to EC2 via GitHub Actions + AWS SSM.

**Required GitHub Secrets:**

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | GitHub Actions IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | GitHub Actions IAM user secret key |
| `EC2_INSTANCE_ID` | EC2 instance ID (`i-xxxxx`) |
| `GH_PAT` | GitHub Personal Access Token (for EC2 to pull code) |

**GitHub Actions IAM user needs these permissions:**
```json
{
  "Action": [
    "ec2:DescribeInstances", "ec2:StartInstances",
    "ssm:DescribeInstanceInformation", "ssm:SendCommand",
    "ssm:GetCommandInvocation", "ssm:ListCommandInvocations"
  ]
}
```

**Deploy flow:**
```
push to main → start EC2 if stopped → wait for SSM → git pull + uv sync + restart service
```

---

## Automated Monthly Retraining

EventBridge fires on the 1st of every month at 2 AM UTC → triggers Lambda → Lambda sends SSM command to EC2 → EC2 runs full training pipeline → new model uploaded to S3.

**Trigger manually:**
```powershell
aws lambda invoke --function-name housing-trigger-training-production response.json
Get-Content response.json
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
| EC2 t2.micro | 24/7 | $0 | ~$8/month |
| S3 | ~500 MB | $0 | ~$0.01/month |
| Lambda | 1/month | $0 | $0 |
| EventBridge | 1 rule | $0 | $0 |
| CloudWatch | ~1 GB logs | $0 | ~$0.50/month |
| Elastic IP | Attached | $0 | $0 |
| **Total** | | **$0** | **~$8-10/month** |

---

## Key Design Decisions

**EC2 + systemd (not ECS/Fargate)** — ECS/Fargate costs $30-35/month. EC2 t2.micro is free for 12 months. For a learning project, EC2 is the right choice.

**Time-based data splits** — Prevents data leakage. Housing prices are time-dependent; random splits would make the model look better than it actually is.

**SSM for remote management** — No open SSH port, no key rotation, full IAM control, automatic CloudWatch logging of every command.

**S3 for model storage** — Models persist independently of EC2 lifecycle. Any service can access them. Built-in versioning.

**MLflow with SQLite** — No separate MLflow server needed. Experiment tracking stored in `/tmp/mlflow.db` on EC2, artifacts in S3.

---

## Further Reading

See `BLOG.md` for a detailed explanation of every component, every AWS service, and lessons learned — written as a Medium article for people learning MLOps.
