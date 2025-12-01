# PowerShell Script: Deploy to AWS
# This script deploys the infrastructure and services to AWS

param(
    [switch]$SkipBuild = $false,
    [string]$Region = "us-west-2"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Deploying to AWS..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

# Check AWS credentials
try {
    aws sts get-caller-identity | Out-Null
} catch {
    Write-Host "Error: AWS credentials not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

Write-Host "AWS Account verified" -ForegroundColor Green

# Build and push Docker images to ECR
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "Building and pushing Docker images to ECR..." -ForegroundColor Green
    
    # Get AWS account ID
    $accountId = (aws sts get-caller-identity --query Account --output text)
    $ecrRegistry = "$accountId.dkr.ecr.$Region.amazonaws.com"
    
    # Login to ECR
    Write-Host "Logging in to ECR..."
    aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $ecrRegistry
    
    # Create ECR repositories if they don't exist
    Write-Host "Creating ECR repositories..."
    aws ecr describe-repositories --repository-names receiver --region $Region 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository --repository-name receiver --region $Region
    }
    
    aws ecr describe-repositories --repository-names processor --region $Region 2>$null
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository --repository-name processor --region $Region
    }
    
    # Build, tag, and push receiver
    Write-Host "Building and pushing receiver..."
    docker build -t receiver:latest ./src/receiver
    docker tag receiver:latest "$ecrRegistry/receiver:latest"
    docker push "$ecrRegistry/receiver:latest"
    
    # Build, tag, and push processor
    Write-Host "Building and pushing processor..."
    docker build -t processor:latest ./src/processor
    docker tag processor:latest "$ecrRegistry/processor:latest"
    docker push "$ecrRegistry/processor:latest"
} else {
    Write-Host "Skipping Docker build (using existing images)" -ForegroundColor Yellow
}

# Deploy infrastructure with Terraform
Write-Host ""
Write-Host "Deploying infrastructure with Terraform..." -ForegroundColor Green

Push-Location infra

# Initialize Terraform
Write-Host "Initializing Terraform..."
terraform init
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

# Apply Terraform configuration for AWS
Write-Host "Applying Terraform configuration..."
terraform apply -var="environment=aws" -auto-approve
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

# Get outputs
Write-Host ""
Write-Host "Infrastructure outputs:" -ForegroundColor Cyan
terraform output

Pop-Location

# Create results directory
if (-not (Test-Path "./results/aws")) {
    New-Item -ItemType Directory -Path "./results/aws" -Force | Out-Null
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Deployment to AWS complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Get the ALB DNS name from the AWS Console or Terraform outputs" -ForegroundColor White
Write-Host "  2. Test the API endpoint" -ForegroundColor White
Write-Host "  3. Run experiments with 04-run-experiments.ps1" -ForegroundColor White
