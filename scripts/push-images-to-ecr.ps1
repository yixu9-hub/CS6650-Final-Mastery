# PowerShell Script: Push Docker Images to ECR
# This script builds and pushes Docker images to AWS ECR

param(
    [string]$Region = "us-west-2"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Pushing Docker Images to ECR" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

# Get AWS account ID
Write-Host ""
Write-Host "Getting AWS account ID..." -ForegroundColor Yellow
try {
    $accountInfo = aws sts get-caller-identity | ConvertFrom-Json
    $accountId = $accountInfo.Account
    Write-Host "Account ID: $accountId" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to get AWS account ID. Are you logged in?" -ForegroundColor Red
    Write-Host "Run: aws configure" -ForegroundColor Yellow
    exit 1
}

$registryUrl = "$accountId.dkr.ecr.$Region.amazonaws.com"

# Check if ECR repositories exist
Write-Host ""
Write-Host "Checking ECR repositories..." -ForegroundColor Yellow
try {
    $repos = aws ecr describe-repositories --region $Region --repository-names order-api order-processor 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: ECR repositories not found" -ForegroundColor Red
        Write-Host "Please create them first with Terraform or run:" -ForegroundColor Yellow
        Write-Host "  aws ecr create-repository --repository-name order-api --region $Region" -ForegroundColor Gray
        Write-Host "  aws ecr create-repository --repository-name order-processor --region $Region" -ForegroundColor Gray
        exit 1
    }
    Write-Host "ECR repositories found!" -ForegroundColor Green
} catch {
    Write-Host "Error checking repositories: $_" -ForegroundColor Red
    exit 1
}

# Login to ECR
Write-Host ""
Write-Host "Logging in to ECR..." -ForegroundColor Yellow
try {
    aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registryUrl
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: ECR login failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "Successfully logged in to ECR!" -ForegroundColor Green
} catch {
    Write-Host "Error during ECR login: $_" -ForegroundColor Red
    exit 1
}

# Build and push receiver image
Write-Host ""
Write-Host "Building receiver image..." -ForegroundColor Yellow
Push-Location ../src/receiver
try {
    docker build -t receiver:latest .
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build receiver image"
    }
    
    docker tag receiver:latest "$registryUrl/order-api:latest"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tag receiver image"
    }
    
    Write-Host "Pushing receiver image to ECR..." -ForegroundColor Yellow
    docker push "$registryUrl/order-api:latest"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push receiver image"
    }
    
    Write-Host "✓ Receiver image pushed successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error with receiver image: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Build and push processor image
Write-Host ""
Write-Host "Building processor image..." -ForegroundColor Yellow
Push-Location ../src/processor
try {
    docker build -t processor:latest .
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build processor image"
    }
    
    docker tag processor:latest "$registryUrl/order-processor:latest"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to tag processor image"
    }
    
    Write-Host "Pushing processor image to ECR..." -ForegroundColor Yellow
    docker push "$registryUrl/order-processor:latest"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to push processor image"
    }
    
    Write-Host "✓ Processor image pushed successfully!" -ForegroundColor Green
} catch {
    Write-Host "Error with processor image: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Verify images in ECR
Write-Host ""
Write-Host "Verifying images in ECR..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Receiver images:" -ForegroundColor Cyan
aws ecr list-images --repository-name order-api --region $Region

Write-Host ""
Write-Host "Processor images:" -ForegroundColor Cyan
aws ecr list-images --repository-name order-processor --region $Region

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Images successfully pushed to ECR!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Deploy ECS services with Terraform:" -ForegroundColor White
Write-Host "     cd infra" -ForegroundColor Gray
Write-Host "     terraform apply -var-file=aws.tfvars -auto-approve" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Get ALB DNS name:" -ForegroundColor White
Write-Host "     terraform output alb_dns_name" -ForegroundColor Gray
