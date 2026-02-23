# Quick Setup Script for AWS S3 Integration
# Run this script to set up your environment for S3 data access

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  AWS S3 Integration Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if AWS CLI is installed
Write-Host "Step 1: Checking AWS CLI installation..." -ForegroundColor Yellow
if (Get-Command aws -ErrorAction SilentlyContinue) {
    Write-Host "✅ AWS CLI is installed" -ForegroundColor Green
    aws --version
} else {
    Write-Host "❌ AWS CLI not found" -ForegroundColor Red
    Write-Host "   Download from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    Write-Host ""
    $install = Read-Host "Would you like to open the download page? (y/n)"
    if ($install -eq 'y') {
        Start-Process "https://aws.amazon.com/cli/"
    }
    exit 1
}
Write-Host ""

# Step 2: Configure AWS credentials
Write-Host "Step 2: Configure AWS Credentials" -ForegroundColor Yellow
Write-Host ""

$configChoice = Read-Host "Do you want to configure AWS credentials now? (y/n)"
if ($configChoice -eq 'y') {
    Write-Host ""
    Write-Host "Please enter your AWS credentials:" -ForegroundColor Cyan
    Write-Host "(Get these from: AWS Console → IAM → Users → Security Credentials)" -ForegroundColor Gray
    Write-Host ""

    # Run aws configure
    aws configure

    Write-Host ""
    Write-Host "✅ AWS credentials configured" -ForegroundColor Green
} else {
    Write-Host "⚠️  Skipping AWS credential configuration" -ForegroundColor Yellow
    Write-Host "   Run 'aws configure' manually when ready" -ForegroundColor Gray
}
Write-Host ""

# Step 3: Test AWS connection
Write-Host "Step 3: Testing AWS Connection..." -ForegroundColor Yellow
try {
    $identity = aws sts get-caller-identity --output json | ConvertFrom-Json
    Write-Host "✅ AWS authentication successful!" -ForegroundColor Green
    Write-Host "   Account ID: $($identity.Account)" -ForegroundColor Gray
    Write-Host "   User ARN: $($identity.Arn)" -ForegroundColor Gray
} catch {
    Write-Host "❌ AWS authentication failed" -ForegroundColor Red
    Write-Host "   Please check your credentials and try again" -ForegroundColor Yellow
}
Write-Host ""

# Step 4: Configure S3 settings
Write-Host "Step 4: Configure S3 Data Source" -ForegroundColor Yellow
Write-Host ""

$useS3 = Read-Host "Will you load data from S3? (y/n)"
if ($useS3 -eq 'y') {
    Write-Host ""
    $bucket = Read-Host "Enter S3 bucket name (e.g., housing-regression-data-production)"
    $key = Read-Host "Enter S3 file key/path (e.g., raw/housing_data.csv)"
    $region = Read-Host "Enter AWS region (default: eu-west-2)"

    if ([string]::IsNullOrWhiteSpace($region)) {
        $region = "eu-west-2"
    }

    # Set environment variables
    $env:USE_S3 = "true"
    $env:S3_DATA_BUCKET = $bucket
    $env:S3_DATA_KEY = $key
    $env:AWS_REGION = $region

    Write-Host ""
    Write-Host "✅ S3 configuration set:" -ForegroundColor Green
    Write-Host "   Bucket: $bucket" -ForegroundColor Gray
    Write-Host "   Key: $key" -ForegroundColor Gray
    Write-Host "   Region: $region" -ForegroundColor Gray

    # Test S3 access
    Write-Host ""
    Write-Host "Testing S3 access..." -ForegroundColor Yellow
    try {
        aws s3 ls "s3://$bucket/$key" --region $region
        Write-Host "✅ Data file found in S3!" -ForegroundColor Green
    } catch {
        Write-Host "⚠️  Could not access data file" -ForegroundColor Yellow
        Write-Host "   Make sure the bucket and file exist" -ForegroundColor Gray
    }

    # Save to .env file
    Write-Host ""
    $saveEnv = Read-Host "Save these settings to .env file? (y/n)"
    if ($saveEnv -eq 'y') {
        # Create .env from template if it doesn't exist
        if (!(Test-Path ".env")) {
            if (Test-Path ".env.template") {
                Copy-Item ".env.template" ".env"
                Write-Host "✅ Created .env from template" -ForegroundColor Green
            } else {
                New-Item ".env" -ItemType File | Out-Null
                Write-Host "✅ Created new .env file" -ForegroundColor Green
            }
        }

        # Update .env with S3 settings
        $envContent = Get-Content ".env" -Raw
        $envContent = $envContent -replace "USE_S3=.*", "USE_S3=true"
        $envContent = $envContent -replace "S3_DATA_BUCKET=.*", "S3_DATA_BUCKET=$bucket"
        $envContent = $envContent -replace "S3_DATA_KEY=.*", "S3_DATA_KEY=$key"
        $envContent = $envContent -replace "AWS_REGION=.*", "AWS_REGION=$region"
        Set-Content ".env" $envContent

        Write-Host "✅ Settings saved to .env" -ForegroundColor Green
    }
} else {
    $env:USE_S3 = "false"
    $localPath = Read-Host "Enter local data file path (default: data/raw/untouched_raw_original.csv)"
    if ([string]::IsNullOrWhiteSpace($localPath)) {
        $localPath = "data/raw/untouched_raw_original.csv"
    }
    $env:LOCAL_DATA_PATH = $localPath

    Write-Host ""
    Write-Host "✅ Local data configuration set:" -ForegroundColor Green
    Write-Host "   Path: $localPath" -ForegroundColor Gray
}
Write-Host ""

# Step 5: Verify setup
Write-Host "Step 5: Verify Complete Setup" -ForegroundColor Yellow
Write-Host ""
Write-Host "Running verification script..." -ForegroundColor Cyan
Write-Host ""

python scripts/verify_aws_setup.py

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run data pipeline: python src/feature_pipeline/load.py" -ForegroundColor Gray
Write-Host "2. Train model: python src/training_pipeline/train.py" -ForegroundColor Gray
Write-Host "3. Start API: python -m uvicorn src.api.main:app --reload" -ForegroundColor Gray
Write-Host ""

