# Build Lambda deployment package for training trigger

Write-Host "Building Lambda deployment package..." -ForegroundColor Green

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Create temporary directory
if (Test-Path "lambda_package") {
    Remove-Item -Recurse -Force "lambda_package"
}
if (Test-Path "lambda_trigger.zip") {
    Remove-Item -Force "lambda_trigger.zip"
}
New-Item -ItemType Directory -Path "lambda_package" | Out-Null

# Copy Lambda function
Copy-Item "lambda_trigger.py" "lambda_package/index.py"

# Create zip file
Compress-Archive -Path "lambda_package\*" -DestinationPath "lambda_trigger.zip"

# Cleanup
Remove-Item -Recurse -Force "lambda_package"

Write-Host "Lambda package created successfully: lambda_trigger.zip" -ForegroundColor Green
Get-Item "lambda_trigger.zip" | Select-Object Name, Length, LastWriteTime
