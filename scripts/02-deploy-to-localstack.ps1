# PowerShell Script: Deploy to LocalStack
# This script deploys the infrastructure and services to LocalStack

param(
    [switch]$SkipBuild = $false
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Deploying to LocalStack..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

# Check if LocalStack is running
try {
    $health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -ErrorAction Stop
    if ($health.services.sqs -ne "available") {
        Write-Host "Error: LocalStack is not running properly" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "Error: Cannot connect to LocalStack. Please start it first with 01-start-localstack.ps1" -ForegroundColor Red
    exit 1
}

# Build Docker images
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "Building Docker images..." -ForegroundColor Green
    
    Write-Host "Building receiver..."
    docker build -t receiver:latest ./src/receiver
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    
    Write-Host "Building processor..."
    docker build -t processor:latest ./src/processor
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} else {
    Write-Host "Skipping Docker build (using existing images)" -ForegroundColor Yellow
}

# Deploy infrastructure with Terraform
Write-Host ""
Write-Host "Deploying infrastructure with Terraform..." -ForegroundColor Green

Push-Location terraform

# Initialize Terraform
Write-Host "Initializing Terraform..."
terraform init
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

# Apply Terraform configuration for LocalStack
Write-Host "Applying Terraform configuration..."
terraform apply -var-file="environments/localstack.tfvars" -auto-approve
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }

# Get outputs
Write-Host ""
Write-Host "Infrastructure outputs:" -ForegroundColor Cyan
terraform output

Pop-Location

# Create results directory
if (-not (Test-Path "./results/localstack")) {
    New-Item -ItemType Directory -Path "./results/localstack" -Force | Out-Null
}

# Wait for ECS services to be ready
Write-Host ""
Write-Host "Waiting for ECS services to be ready..." -ForegroundColor Yellow
Write-Host "Note: Services are deployed via Terraform to LocalStack ECS" -ForegroundColor Cyan
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Deployment to LocalStack complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Services:" -ForegroundColor Cyan
Write-Host "  - Receiver API (ECS): http://localhost:8080" -ForegroundColor White
Write-Host "  - LocalStack Gateway: http://localhost:4566" -ForegroundColor White
Write-Host ""
Write-Host "Test the API:" -ForegroundColor Cyan
Write-Host '  curl -X POST http://localhost:8080/orders/async -H "Content-Type: application/json" -d ''{"order_id":"test123","customer_id":1,"items":[{"product_id":"p1","quantity":2,"price":10.5}]}''' -ForegroundColor White
Write-Host ""
Write-Host "View ECS logs:" -ForegroundColor Cyan
Write-Host "  docker ps  # Find ECS container names" -ForegroundColor Gray
Write-Host "  docker logs -f <container-name>" -ForegroundColor Gray
