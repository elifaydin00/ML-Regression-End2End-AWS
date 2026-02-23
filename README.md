# Housing Regression ML - End-to-End Project

> **Production-ready ML pipeline for housing price prediction using XGBoost, deployed on AWS EC2 Free Tier**

---

## 📋 Table of Contents

1. [Project Overview](#-project-overview)
2. [Architecture](#-architecture)
3. [Prerequisites](#-prerequisites)
4. [Step 1: Local Development Setup](#-step-1-local-development-setup)
5. [Step 2: Run the ML Pipeline Locally](#-step-2-run-the-ml-pipeline-locally)
6. [Step 3: Test the API Locally](#-step-3-test-the-api-locally)
7. [Step 4: AWS Account Setup](#-step-4-aws-account-setup)
8. [Step 5: Deploy Infrastructure to AWS](#-step-5-deploy-infrastructure-to-aws)
9. [Step 6: Deploy Application to EC2](#-step-6-deploy-application-to-ec2)
10. [Step 7: Monitor and Maintain](#-step-7-monitor-and-maintain)
11. [Common Operations](#-common-operations)
12. [Project Structure](#-project-structure)
13. [Testing](#-testing)
14. [Troubleshooting](#-troubleshooting)
15. [Cost Information](#-cost-information)

---

## 📖 Project Overview

This is a **production-ready, end-to-end machine learning system** for predicting housing prices. It demonstrates best practices in ML engineering:

### Key Features

✅ **Complete ML Pipeline**: Load → Preprocess → Feature Engineering → Train → Evaluate → Inference → Deploy  
✅ **AWS Deployment**: Runs on EC2 Free Tier ($0 for 12 months)  
✅ **Automated Training**: Monthly retraining via Lambda + EventBridge  
✅ **REST API**: FastAPI service with automatic documentation  
✅ **Cloud Storage**: S3 for model versioning and data storage  
✅ **Monitoring**: CloudWatch logs and metrics  
✅ **Testing**: Comprehensive test suite with pytest  
✅ **IaC**: Infrastructure as Code with Terraform  
✅ **Experiment Tracking**: MLflow integration  
✅ **Data Quality**: Great Expectations validation  

### What You'll Learn

- Building production ML pipelines
- AWS infrastructure (EC2, S3, Lambda, EventBridge, CloudWatch, IAM)
- Infrastructure as Code (Terraform)
- API development (FastAPI)
- Model deployment and versioning
- Automated training pipelines
- Cost optimization on AWS

---

## 🏗️ Architecture

### System Flow

```
┌─────────────────────────────────────────────────────────┐
│              ML PIPELINE ARCHITECTURE                   │
└─────────────────────────────────────────────────────────┘

Data Loading → Preprocessing → Feature Engineering
                                       ↓
                           Training (XGBoost)
                                       ↓
                           Model Evaluation
                                       ↓
                           Save to S3 (if AWS) or Local
                                       ↓
                           FastAPI Inference Service
```

### AWS Deployment Architecture

```
┌──────────────┐
│ EventBridge  │  ← Monthly schedule (1st @ 2 AM UTC)
└──────┬───────┘
       │ Triggers
       ▼
┌──────────────┐
│   Lambda     │  ← Sends command to EC2
└──────┬───────┘
       │ SSM Command
       ▼
┌─────────────────────────────────────────┐
│     EC2 t2.micro (Free Tier)            │
│                                         │
│  ┌─────────────┐   ┌─────────────┐    │
│  │   FastAPI   │   │  Training   │    │
│  │  (Port 8000)│   │   Script    │    │
│  └──────┬──────┘   └──────┬──────┘    │
│         │                 │            │
└─────────┼─────────────────┼────────────┘
          │                 │
          └────────┬────────┘
                   ▼
          ┌───────────────┐
          │   S3 Bucket   │  ← Models, Data, Versions
          └───────┬───────┘
                  │
                  ▼
          ┌───────────────┐
          │  CloudWatch   │  ← Logs & Monitoring
          └───────────────┘
```

### Core Modules

- **`src/feature_pipeline/`**: Data loading, preprocessing, feature engineering
  - `load.py`: Time-aware data splitting (train <2020, eval 2020-21, holdout ≥2022)
  - `preprocess.py`: City normalization, deduplication, outlier removal
  - `feature_engineering.py`: Date features, frequency/target encoding

- **`src/training_pipeline/`**: Model training and optimization
  - `train.py`: XGBoost training with S3 integration
  - `tune.py`: Optuna hyperparameter tuning with MLflow
  - `eval.py`: Model evaluation and metrics

- **`src/inference_pipeline/`**: Production inference
  - `inference.py`: Applies transformations using saved encoders

- **`src/api/`**: FastAPI web service
  - `main.py`: REST API with health checks, predictions, batch processing

- **`src/batch/`**: Batch processing
  - `run_monthly.py`: Monthly predictions on holdout data

---

## 🔧 Prerequisites

Before starting, ensure you have:

### Required Software

- **Python 3.11+** - [Download](https://www.python.org/downloads/)
- **uv** - Fast Python package manager: `pip install uv`
- **Git** - [Download](https://git-scm.com/downloads)
- **AWS CLI** - [Download](https://aws.amazon.com/cli/) (for AWS deployment)
- **Terraform** >= 1.0 - [Download](https://www.terraform.io/downloads) (for AWS deployment)

### AWS Requirements (for cloud deployment)

- **AWS Free Tier Account** - [Sign up](https://aws.amazon.com/free/)
- **AWS Access Keys** - IAM user with admin permissions
- **SSH Client** - Built into Windows 10+, macOS, Linux

### Check Prerequisites

```powershell
# Check Python version
python --version  # Should be 3.11+

# Check uv
uv --version

# Check Git
git --version

# Check AWS CLI (for deployment)
aws --version

# Check Terraform (for deployment)
terraform --version
```

---

## 🚀 Step 1: Local Development Setup

### 1.1 Clone Repository

```powershell
cd C:\Users\YourName\Projects  # Or your preferred directory
git clone <your-repo-url>
cd Regression_ML_EndtoEnd
```

### 1.2 Install Dependencies

```powershell
# Install all dependencies with uv
uv sync

# This installs everything from pyproject.toml including:
# - xgboost, scikit-learn (ML)
# - fastapi, uvicorn (API)
# - boto3 (AWS)
# - mlflow (experiment tracking)
# - great-expectations (data quality)
# - pytest (testing)
```

### 1.3 Verify Installation

```powershell
# Check installed packages
uv pip list

# Run a quick test
uv run pytest tests/ -v
```

---

## 📊 Step 2: Run the ML Pipeline Locally

### 2.1 Configure AWS Credentials (for S3 data access)

**If your dataset is in S3**, configure your AWS credentials first:

```powershell
# Method 1: AWS CLI (Recommended)
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: us-east-1
# Default output format: json

# Verify credentials
aws sts get-caller-identity

# Method 2: Environment Variables
$env:AWS_ACCESS_KEY_ID = "your_access_key_here"
$env:AWS_SECRET_ACCESS_KEY = "your_secret_key_here"
$env:AWS_REGION = "us-east-1"

# Verify AWS setup
uv run python scripts/verify_aws_setup.py
```

### 2.2 Load Dataset

**Option A: Load from S3 (Production)**

```powershell
# Configure S3 data source
$env:USE_S3 = "true"
$env:S3_DATA_BUCKET = "house-forecast"
$env:S3_DATA_KEY = "raw/HouseTS.csv"
$env:AWS_REGION = "us-east-1"

# Run data loading (will download from S3)
uv run python src/feature_pipeline/load.py

# Output:
# Loading data from S3: s3://house-forecast/raw/HouseTS.csv
# Data split completed
```

**Option B: Load from Local File**

```powershell
# Use local data file (default path)
$env:USE_S3 = "false"
$env:LOCAL_DATA_PATH = "data/raw/HouseTS.csv"

# Run data loading
uv run python src/feature_pipeline/load.py
```

### 2.3 Run Data Pipeline

```powershell
# Step 1: Load and split data (already done above)
# This creates: data/processed/train.csv, eval.csv, holdout.csv

# Step 2: Preprocess data (clean, normalize, remove outliers)
uv run python src/feature_pipeline/preprocess.py

# Step 3: Feature engineering (date features, encoding)
uv run python src/feature_pipeline/feature_engineering.py

# Output:
# - data/processed/train_processed.csv
# - data/processed/eval_processed.csv
# - models/freq_encoder.pkl
# - models/target_encoder.pkl
```

### 2.4 Train Model

```powershell
# Train XGBoost model locally
$env:USE_S3 = "false"  # Use local storage
uv run python src/training_pipeline/train.py

# Output:
# - models/xgb_model.pkl (trained model)
# - Metrics printed to console
```

### 2.5 Optional: Hyperparameter Tuning

```powershell
# Run Optuna-based tuning with MLflow tracking
uv run python src/training_pipeline/tune.py

# This will:
# - Run multiple trials with different hyperparameters
# - Track experiments in MLflow (SQLite store: mlflow.db)
# - Save best model as models/xgb_best_model.pkl

# View MLflow UI (uses local SQLite tracking store)
uv run mlflow ui --backend-store-uri sqlite:///mlflow.db

# Open browser: http://localhost:5000
```

### 2.6 Evaluate Model

```powershell
# Evaluate on holdout set
uv run python src/training_pipeline/eval.py

# View metrics:
# - MAE, RMSE, R²
# - Feature importance plots
```

---

## 🌐 Step 3: Test the API Locally

### 3.1 Start FastAPI Server

```powershell
# Start the API server
$env:USE_S3 = "false"  # Use local models
uv run uvicorn src.api.main:app --host 0.0.0.0 --port 8000 --reload

# Server starts at: http://localhost:8000
```

### 3.2 Test API Endpoints

**Open API Documentation** (recommended):
```powershell
Start-Process "http://localhost:8000/docs"
```

**Or use PowerShell/curl**:

```powershell
# Health check
Invoke-RestMethod -Uri "http://localhost:8000/health"

# Single prediction
$body = @{
    MedInc = 3.5
    HouseAge = 25.0
    AveRooms = 5.0
    AveBedrms = 1.2
    Population = 1000.0
    AveOccup = 3.0
    Latitude = 37.5
    Longitude = -122.0
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:8000/predict" -Method Post -Body $body -ContentType "application/json"

# Expected output:
# {
#   "prediction": 2.85,
#   "model_version": "xgb_model"
# }
```

---

## ☁️ Step 4: AWS Account Setup

### 4.1 Create AWS Account

1. Go to [aws.amazon.com](https://aws.amazon.com)
2. Click "Create an AWS Account"
3. Follow the registration process
4. **Important**: Select **Free Tier** eligible options

### 4.2 Create IAM User with Access Keys

```powershell
# Option A: Via AWS Console (easier)
# 1. Go to IAM → Users → Create User
# 2. Username: terraform-user
# 3. Permissions: AdministratorAccess (for learning)
# 4. Create access keys → Download credentials

# Option B: Via AWS CLI (if you have root credentials)
aws iam create-user --user-name terraform-user
aws iam attach-user-policy --user-name terraform-user --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam create-access-key --user-name terraform-user > aws-credentials.json
```

### 4.3 Configure AWS CLI

```powershell
# Configure AWS CLI with your credentials
aws configure

# Enter:
# AWS Access Key ID: [your-access-key-id]
# AWS Secret Access Key: [your-secret-access-key]
# Default region name: us-east-1
# Default output format: json

# Test configuration
aws sts get-caller-identity
```

### 4.4 Create SSH Key for EC2

```powershell
# Create .ssh directory if it doesn't exist
if (!(Test-Path "$env:USERPROFILE\.ssh")) {
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.ssh"
}

# Create EC2 key pair
aws ec2 create-key-pair `
  --key-name housing-ml-key `
  --query 'KeyMaterial' `
  --output text `
  --region us-east-1 | Out-File -Encoding ASCII "$env:USERPROFILE\.ssh\housing-ml-key.pem"

Write-Host "✅ SSH key created: $env:USERPROFILE\.ssh\housing-ml-key.pem" -ForegroundColor Green
```

---

## 🚢 Step 5: Deploy Infrastructure to AWS

### 5.1 Upload Data and Models to S3

First, create S3 bucket and upload your trained models:

```powershell
# Set environment variables
$env:S3_BUCKET = "house-forecast"
$env:AWS_REGION = "us-east-1"
$env:USE_S3 = "true"

# Make sure AWS credentials are configured (~/.aws/credentials)
aws sts get-caller-identity

# Upload data and models to S3
uv run python src/data/upload_to_s3.py

# This uploads:
# - data/ → s3://bucket/data/
# - models/ → s3://bucket/models/production/
```

### 5.2 Build Lambda Package

```powershell
# Navigate to terraform directory
cd terraform

# Build Lambda deployment package
.\build_lambda.ps1

# This creates lambda_trigger.zip

cd ..
```

### 5.3 Deploy with Terraform

```powershell
cd terraform

# Initialize Terraform (first time only)
terraform init

# Review what will be created
terraform plan -var="github_repo_url=https://github.com/YOUR_USERNAME/YOUR_REPO.git"

# Deploy infrastructure
terraform apply -var="github_repo_url=https://github.com/YOUR_USERNAME/YOUR_REPO.git"

# Type 'yes' when prompted

# Wait 5-10 minutes for deployment
```

### 5.4 Save Infrastructure Outputs

```powershell
# Save important outputs
$EC2_IP = terraform output -raw ec2_public_ip
$S3_BUCKET = terraform output -raw s3_bucket_name
$API_URL = terraform output -raw api_url

Write-Host "✅ Infrastructure deployed!" -ForegroundColor Green
Write-Host "EC2 Public IP: $EC2_IP" -ForegroundColor Cyan
Write-Host "S3 Bucket: $S3_BUCKET" -ForegroundColor Cyan
Write-Host "API URL: $API_URL" -ForegroundColor Cyan

# Save to file for later use
@"
EC2_IP=$EC2_IP
S3_BUCKET=$S3_BUCKET
API_URL=$API_URL
"@ | Out-File -FilePath "..\aws-outputs.env"

cd ..
```

**What Terraform Created**:
- ✅ EC2 t2.micro instance (Free Tier)
- ✅ S3 bucket for models/data
- ✅ Lambda function for training trigger
- ✅ EventBridge rule for monthly schedule
- ✅ CloudWatch log group
- ✅ IAM roles and policies
- ✅ Security groups
- ✅ Elastic IP

---

## 📦 Step 6: Deploy Application to EC2

### 6.1 Wait for EC2 Initialization

The EC2 instance needs time to install Docker, Python, and dependencies.

```powershell
Write-Host "⏳ Waiting for EC2 to initialize (5 minutes)..." -ForegroundColor Yellow
Write-Host "The instance is installing Python 3.11, uv, AWS CLI, and cloning the repo..." -ForegroundColor Cyan

# Wait 5 minutes
Start-Sleep -Seconds 300

# Test SSH connection
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "echo '✅ EC2 is ready!'"
```

### 6.2 Deploy Application Code

```powershell
# Set environment variables
$env:EC2_IP = $EC2_IP
$env:S3_BUCKET = $S3_BUCKET

# Deploy using PowerShell script
.\scripts\deploy_to_ec2.ps1

# This script:
# 1. Syncs your code to EC2
# 2. Installs Python dependencies
# 3. Downloads models from S3
# 4. Configures the environment
```

### 6.3 Start API Service

The API is managed by **systemd** (set up automatically during EC2 initialization).

```powershell
# SSH into EC2 and check service status
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP

# On EC2, check API status:
sudo systemctl status housing-ml-api

# Start or restart if needed:
sudo systemctl start housing-ml-api
sudo systemctl restart housing-ml-api

# Exit SSH
exit
```

### 6.4 Test Deployed API

```powershell
# Wait for API to start
Start-Sleep -Seconds 10

# Test health endpoint
Invoke-RestMethod -Uri "http://${EC2_IP}:8000/health"

# Test prediction
$body = @{
    MedInc = 3.5
    HouseAge = 25.0
    AveRooms = 5.0
    AveBedrms = 1.2
    Population = 1000.0
    AveOccup = 3.0
    Latitude = 37.5
    Longitude = -122.0
} | ConvertTo-Json

$result = Invoke-RestMethod -Uri "http://${EC2_IP}:8000/predict" -Method Post -Body $body -ContentType "application/json"
Write-Host "Prediction: $($result.prediction)" -ForegroundColor Green

# Open API documentation
Start-Process "http://${EC2_IP}:8000/docs"
```

**🎉 Congratulations! Your ML API is now live on AWS!**

---

## 📊 Step 7: Monitor and Maintain

### 7.1 View Logs

**CloudWatch Logs** (AWS Console):
```powershell
# Via AWS CLI
aws logs tail /ec2/housing-ml --follow --region us-east-1

# Or open AWS Console → CloudWatch → Log Groups → /ec2/housing-ml
```

**SSH into EC2**:
```powershell
# View API logs
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "tail -f /var/log/housing-ml/api.log"

# View training logs
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "tail -f /var/log/housing-ml/training.log"
```

### 7.2 Monitor Training Schedule

**Automated training** runs **monthly on the 1st at 2 AM UTC**.

Check EventBridge:
```powershell
# List scheduled rules
aws events list-rules --region us-east-1

# Check Lambda function logs
aws logs tail /aws/lambda/housing-trigger-training-production --follow --region us-east-1
```

### 7.3 Trigger Manual Training

```powershell
# Trigger training immediately
aws lambda invoke `
  --function-name housing-trigger-training-production `
  --region us-east-1 `
  response.json

Get-Content response.json

# Or via SSH
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "/opt/housing-ml/run_training.sh"
```

### 7.4 Check Model Versions in S3

```powershell
# List production models
aws s3 ls s3://$S3_BUCKET/models/production/

# List versioned models
aws s3 ls s3://$S3_BUCKET/models/versions/
```

---

## 🛠️ Common Operations

### Update Application Code

```powershell
# Make changes to your code locally
# Then deploy updates:

$env:EC2_IP = $EC2_IP
.\scripts\deploy_to_ec2.ps1

# Restart API
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "sudo systemctl restart housing-ml-api"
```

### Restart API Service

```powershell
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "sudo systemctl restart housing-ml-api"
```

### View System Status

```powershell
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP

# On EC2:
sudo systemctl status housing-ml-api  # Service status
df -h  # Disk usage
free -h  # Memory usage
top  # CPU usage
docker ps  # Running containers (if using Docker)
```

### Download Models from S3

```powershell
# Download latest production model
aws s3 cp s3://$S3_BUCKET/models/production/xgb_model.pkl models/

# Download all models
aws s3 sync s3://$S3_BUCKET/models/ models/
```

### Run Tests

```powershell
# Run all tests
uv run pytest

# Run specific test file
uv run pytest tests/test_inference.py -v

# Run with coverage
uv run pytest --cov=src --cov-report=html
```

### Destroy Infrastructure (Cleanup)

```powershell
cd terraform

# Destroy all AWS resources
terraform destroy

# Type 'yes' when prompted

# Manually delete S3 bucket contents if needed
aws s3 rm s3://$S3_BUCKET --recursive
aws s3 rb s3://$S3_BUCKET

cd ..
```

---

## 📁 Project Structure

```
Regression_ML_EndtoEnd/
├── src/
│   ├── feature_pipeline/
│   │   ├── load.py                    # Download & split data by year
│   │   ├── preprocess.py              # Clean & normalize
│   │   └── feature_engineering.py     # Encoding & feature creation
│   ├── training_pipeline/
│   │   ├── train.py                   # Train XGBoost model
│   │   ├── tune.py                    # Hyperparameter tuning (Optuna)
│   │   └── eval.py                    # Model evaluation
│   ├── inference_pipeline/
│   │   └── inference.py               # Production inference
│   ├── api/
│   │   └── main.py                    # FastAPI application
│   ├── batch/
│   │   └── run_monthly.py             # Batch predictions
│   └── data/
│       └── upload_to_s3.py            # Upload data/models to S3
├── terraform/
│   ├── main.tf                        # Infrastructure definition (EC2, S3, Lambda)
│   ├── user_data.sh                   # EC2 initialization script
│   ├── lambda_trigger.py              # Training trigger Lambda function
│   ├── build_lambda.ps1               # Build Lambda package (Windows)
│   └── build_lambda.sh                # Build Lambda package (Linux/Mac)
├── scripts/
│   ├── deploy_to_ec2.ps1              # Deploy app to EC2 (Windows)
│   └── deploy_to_ec2.sh               # Deploy app to EC2 (Linux/Mac)
├── tests/
│   ├── test_features.py               # Test feature engineering
│   ├── test_training.py               # Test training pipeline
│   ├── test_inference.py              # Test inference
│   └── data_quality.py                # Data quality checks (Great Expectations)
├── data/
│   ├── raw/                           # Original data
│   └── processed/                     # Processed data splits
├── models/                             # Trained models & encoders
│   ├── xgb_model.pkl
│   ├── freq_encoder.pkl
│   └── target_encoder.pkl
├── configs/
│   ├── app_config.yml                 # Application configuration
│   ├── mlflow_config.yml              # MLflow settings
│   └── ge_expectations.yml            # Data quality expectations
├── app.py                             # Streamlit dashboard
├── Dockerfile                         # API container
├── Dockerfile.train                   # Training container
├── pyproject.toml                     # Python dependencies
├── pytest.ini                         # Test configuration
└── README.md                          # This file
```

---

## 🧪 Testing

### Run All Tests

```powershell
uv run pytest
```

### Run Specific Test Modules

```powershell
# Test feature engineering
uv run pytest tests/test_features.py -v

# Test training pipeline
uv run pytest tests/test_training.py -v

# Test inference
uv run pytest tests/test_inference.py -v

# Test data quality
uv run pytest tests/data_quality.py -v
```

### Run with Coverage

```powershell
uv run pytest --cov=src --cov-report=html

# Open coverage report
Start-Process "htmlcov/index.html"
```

---

## 🔍 Troubleshooting

### Issue: Cannot SSH into EC2

```powershell
# Check if instance is running
aws ec2 describe-instances --instance-ids $EC2_INSTANCE_ID

# Check security group allows your IP
$MY_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
Write-Host "Your IP: ${MY_IP}/32"

# Update security group to allow your IP (via Terraform or AWS Console)
```

### Issue: API Not Responding

```powershell
# Check if API is running
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "ps aux | grep uvicorn"

# Check logs
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "tail -n 100 /var/log/housing-ml/api.log"

# Restart API via systemd
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "sudo systemctl restart housing-ml-api"
```

### Issue: Models Not Loading

```powershell
# Check if models exist in S3
aws s3 ls s3://$S3_BUCKET/models/production/

# Download models manually to EC2
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP @"
cd /opt/housing-ml/app
aws s3 sync s3://$S3_BUCKET/models/production/ models/
"@
```

### Issue: Training Fails

```powershell
# Check training logs
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP "cat /var/log/housing-ml/training.log"

# Run training manually for debugging
ssh -i "$env:USERPROFILE\.ssh\housing-ml-key.pem" ec2-user@$EC2_IP @"
cd /opt/housing-ml/app
export USE_S3=true
export S3_BUCKET=house-forecast
.venv/bin/python src/training_pipeline/train.py
"@
```

### Issue: Lambda Not Triggering Training

```powershell
# Test Lambda function
aws lambda invoke `
  --function-name housing-trigger-training-production `
  --region us-east-1 `
  response.json

Get-Content response.json

# Check Lambda logs
aws logs tail /aws/lambda/housing-trigger-training-production --follow --region us-east-1
```

### Issue: Permission Denied

```powershell
# Fix SSH key permissions (Windows)
icacls "$env:USERPROFILE\.ssh\housing-ml-key.pem" /inheritance:r
icacls "$env:USERPROFILE\.ssh\housing-ml-key.pem" /grant:r "$env:USERNAME`:R"
```

---

## 💰 Cost Information

### AWS Free Tier (First 12 Months)

| Service | Free Tier Limit | This Project | Cost |
|---------|-----------------|--------------|------|
| **EC2 t2.micro** | 750 hours/month | 720 hours (24/7) | **$0** |
| **S3 Storage** | 5 GB | ~500 MB | **$0** |
| **Lambda** | 1M requests | ~12/month | **$0** |
| **CloudWatch Logs** | 5 GB ingestion | ~1 GB/month | **$0** |
| **Elastic IP** | 1 free (attached) | 1 | **$0** |
| **EventBridge** | Unlimited rules | 1 | **$0** |
| **Data Transfer** | 100 GB out | <1 GB | **$0** |
| **Total** | | | **$0/month** ✅ |

### After Free Tier (Month 13+)

| Service | Monthly Cost |
|---------|--------------|
| EC2 t2.micro (730 hrs) | ~$8.00 |
| S3 Storage (500 MB) | $0.12 |
| Lambda (12 invocations) | $0.00 |
| CloudWatch Logs | $0.50 |
| Elastic IP | $0.00 |
| **Total** | **~$8-10/month** |

### Cost Optimization Tips

1. **Stop EC2 when not needed**: Save ~$8/month
   ```powershell
   aws ec2 stop-instances --instance-ids $EC2_INSTANCE_ID
   aws ec2 start-instances --instance-ids $EC2_INSTANCE_ID
   ```

2. **Use smaller instance**: t2.nano costs ~$4/month (but may be slow)

3. **Clean up old S3 versions**: Enable lifecycle policies

4. **Set billing alerts**: AWS Console → Billing → Budgets

---

## 🎓 Key Concepts Demonstrated

### ML Engineering Best Practices

✅ **Time-based data splits** - Prevents data leakage  
✅ **Encoder persistence** - Save/load transformations  
✅ **Model versioning** - Track model history in S3  
✅ **Experiment tracking** - MLflow for hyperparameter tuning  
✅ **Data validation** - Great Expectations for quality checks  
✅ **Automated retraining** - Monthly updates with new data  

### AWS & DevOps

✅ **Infrastructure as Code** - Terraform for reproducibility  
✅ **Serverless scheduling** - Lambda + EventBridge  
✅ **Object storage** - S3 for model artifacts  
✅ **Compute instances** - EC2 for API hosting  
✅ **Monitoring** - CloudWatch logs and metrics  
✅ **IAM security** - Principle of least privilege  

### Software Engineering

✅ **API development** - FastAPI with automatic docs  
✅ **Testing** - pytest with comprehensive coverage  
✅ **Modular design** - Separate pipelines for each stage  
✅ **Configuration management** - YAML configs  
✅ **Dependency management** - pyproject.toml with uv  
✅ **Documentation** - Comprehensive README  

---

## 📚 Additional Resources

### Documentation
- [FastAPI Docs](https://fastapi.tiangolo.com/)
- [XGBoost Guide](https://xgboost.readthedocs.io/)
- [AWS Free Tier](https://aws.amazon.com/free/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [MLflow Tracking](https://mlflow.org/docs/latest/tracking.html)

### Tutorials
- [AWS EC2 Getting Started](https://docs.aws.amazon.com/ec2/)
- [Terraform Getting Started](https://learn.hashicorp.com/terraform)
- [FastAPI Tutorial](https://fastapi.tiangolo.com/tutorial/)

### Related Projects
- [MLOps Best Practices](https://ml-ops.org/)
- [AWS ML Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/machine-learning-lens/)

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

---

## 📄 License

This project is for educational purposes. Feel free to use and modify as needed.

---

## 🎉 Congratulations!

You now have a **production-ready ML pipeline** running on **AWS Free Tier**!

**What you've built:**
- ✅ End-to-end ML pipeline
- ✅ REST API with FastAPI
- ✅ AWS cloud deployment
- ✅ Automated training
- ✅ Model versioning in S3
- ✅ Monitoring with CloudWatch
- ✅ Infrastructure as Code

**Next steps:**
- 🚀 Add more features
- 📊 Build dashboards
- 🔄 Implement CI/CD
- 📈 Scale to larger datasets
- 🤖 Try different models

---

**Questions or issues?** Check the Troubleshooting section or open an issue on GitHub.

**Happy ML Engineering! 🚀**

