# Deploy application to EC2 instance (PowerShell)

param(
    [Parameter(Mandatory=$false)]
    [string]$EC2_IP = $env:EC2_IP,

    [Parameter(Mandatory=$false)]
    [string]$SSH_KEY = "$env:USERPROFILE\.ssh\housing-ml-key.pem"
)

if ([string]::IsNullOrEmpty($EC2_IP)) {
    Write-Host "❌ Error: EC2_IP not set" -ForegroundColor Red
    Write-Host "Usage: .\scripts\deploy_to_ec2.ps1 -EC2_IP 1.2.3.4" -ForegroundColor Yellow
    Write-Host "Or set environment variable: `$env:EC2_IP='1.2.3.4'" -ForegroundColor Yellow
    exit 1
}

Write-Host "🚀 Deploying to EC2: $EC2_IP" -ForegroundColor Green
Write-Host "SSH Key: $SSH_KEY" -ForegroundColor Cyan

$APP_DIR = "/opt/housing-ml/app"

# Create app directory on EC2
Write-Host "📁 Creating app directory on EC2..." -ForegroundColor Cyan
ssh -i $SSH_KEY ec2-user@$EC2_IP "sudo mkdir -p $APP_DIR && sudo chown ec2-user:ec2-user $APP_DIR"

# Use SCP or rsync (if available via WSL or Git Bash)
Write-Host "📦 Uploading code to EC2..." -ForegroundColor Cyan
Write-Host "⚠️ Using scp. For faster sync, use WSL with rsync" -ForegroundColor Yellow

# Create a temporary zip file
$tempZip = "$env:TEMP\housing-ml-deploy.zip"
if (Test-Path $tempZip) {
    Remove-Item $tempZip -Force
}

# Compress project (excluding unnecessary files)
$excludeDirs = @(".git", "__pycache__", ".pytest_cache", "data", "models", ".venv", "venv")
$excludeExtensions = @(".pyc")
$excludeNamePatterns = @("*.egg-info")

Write-Host "Creating deployment package..." -ForegroundColor Cyan

# Collect files to include, filtering out excluded paths
$filesToInclude = Get-ChildItem -Recurse -File | Where-Object {
    $file = $_
    $relativePath = $file.FullName.Substring((Get-Location).Path.Length + 1)

    # Exclude files inside excluded directories
    $inExcludedDir = $excludeDirs | Where-Object { $relativePath -match "(^|\\)$([regex]::Escape($_))(\\|$)" }
    # Exclude by extension
    $hasExcludedExt = $excludeExtensions -contains $file.Extension
    # Exclude by name pattern
    $matchesNamePattern = $excludeNamePatterns | Where-Object { $file.Name -like $_ }

    -not $inExcludedDir -and -not $hasExcludedExt -and -not $matchesNamePattern
}

if ($filesToInclude) {
    Compress-Archive -Path $filesToInclude.FullName -DestinationPath $tempZip -Force
} else {
    Write-Host "No files to compress." -ForegroundColor Yellow
    exit 1
}

# Upload and extract
scp -i $SSH_KEY $tempZip ec2-user@${EC2_IP}:/tmp/housing-ml-deploy.zip
ssh -i $SSH_KEY ec2-user@$EC2_IP @"
cd $APP_DIR
unzip -o /tmp/housing-ml-deploy.zip
rm /tmp/housing-ml-deploy.zip
"@

# Clean up local temp file
Remove-Item $tempZip -Force

# Install dependencies
Write-Host "📥 Installing dependencies on EC2..." -ForegroundColor Cyan
ssh -i $SSH_KEY ec2-user@$EC2_IP @'
cd /opt/housing-ml/app

# Install uv if not present
if ! command -v uv &> /dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Create virtual environment
if [ ! -d "venv" ]; then
    python3.11 -m venv venv
fi

source venv/bin/activate
uv pip install -e .

# Create models directory
mkdir -p models

# Download models from S3
if [ "$USE_S3" = "true" ] && [ -n "$S3_BUCKET" ]; then
    echo "Downloading models from S3..."
    aws s3 sync s3://$S3_BUCKET/models/ models/ || echo "No models in S3 yet"
fi

echo "Dependencies installed successfully"
'@

# Restart API service
Write-Host "🔄 Restarting API service..." -ForegroundColor Cyan
ssh -i $SSH_KEY ec2-user@$EC2_IP "sudo systemctl restart housing-ml-api || echo 'Service not configured yet'"

Write-Host ""
Write-Host "✅ Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "API URL: http://$EC2_IP:8000" -ForegroundColor Cyan
Write-Host "API Docs: http://$EC2_IP:8000/docs" -ForegroundColor Cyan
Write-Host ""
Write-Host "To view logs:" -ForegroundColor Yellow
Write-Host "  ssh -i $SSH_KEY ec2-user@$EC2_IP 'tail -f /var/log/housing-ml/api.log'" -ForegroundColor Gray

