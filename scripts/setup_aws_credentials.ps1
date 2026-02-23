# AWS Credentials Setup Guide
# Run these commands to configure your AWS credentials

# ============================================
# Method 1: AWS CLI (Recommended)
# ============================================

# Install AWS CLI if not already installed
# Download from: https://aws.amazon.com/cli/

# Configure AWS credentials interactively
aws configure

# This will prompt for:
# - AWS Access Key ID
# - AWS Secret Access Key
# - Default region (eu-west-2)
# - Default output format (json)

# Verify configuration
aws sts get-caller-identity

# ============================================
# Method 2: Environment Variables (Project-specific)
# ============================================

# Copy the template
Copy-Item .env.template .env

# Edit .env file and add your credentials:
# AWS_ACCESS_KEY_ID=your_actual_access_key
# AWS_SECRET_ACCESS_KEY=your_actual_secret_key
# AWS_REGION=eu-west-2

# Load environment variables (PowerShell)
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

# Or use python-dotenv (install first: pip install python-dotenv)
# Then in your Python code:
# from dotenv import load_dotenv
# load_dotenv()

# ============================================
# Method 3: Manual Environment Variables
# ============================================

# Set for current session (PowerShell)
$env:AWS_ACCESS_KEY_ID = "your_access_key_here"
$env:AWS_SECRET_ACCESS_KEY = "your_secret_key_here"
$env:AWS_REGION = "eu-west-2"

# Set permanently (PowerShell - Admin required)
[System.Environment]::SetEnvironmentVariable('AWS_ACCESS_KEY_ID', 'your_access_key_here', 'User')
[System.Environment]::SetEnvironmentVariable('AWS_SECRET_ACCESS_KEY', 'your_secret_key_here', 'User')
[System.Environment]::SetEnvironmentVariable('AWS_REGION', 'eu-west-2', 'User')

# ============================================
# Verify AWS Access
# ============================================

# Test S3 access
aws s3 ls

# List your buckets
aws s3 ls

# Test specific bucket access
aws s3 ls s3://housing-regression-data-production/

# ============================================
# Security Best Practices
# ============================================

# 1. NEVER commit .env file to git (it's in .gitignore)
# 2. Use IAM user with minimal permissions (not root account)
# 3. Rotate credentials regularly
# 4. For production, use IAM roles instead of access keys

# Create IAM user with S3 access:
# AWS Console → IAM → Users → Add User
# - Username: housing-ml-user
# - Access type: Programmatic access
# - Permissions: AmazonS3ReadOnlyAccess (or custom policy)
# - Download credentials CSV

# ============================================
# Required IAM Permissions
# ============================================

# Minimum permissions needed for this project:
<#
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::housing-regression-data-production",
        "arn:aws:s3:::housing-regression-data-production/*"
      ]
    }
  ]
}
#>

