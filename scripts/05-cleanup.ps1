# PowerShell Script: Cleanup
# This script cleans up all resources

param(
    [string]$Environment = "both" # "localstack", "aws", or "both"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Cleaning up resources for: $Environment" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

function Cleanup-LocalStack {
    Write-Host ""
    Write-Host "Cleaning up LocalStack..." -ForegroundColor Yellow
    
    # Destroy Terraform infrastructure first
    Write-Host "Destroying LocalStack Terraform infrastructure..."
    Push-Location infra
    try {
        terraform workspace select default 2>$null
        terraform destroy -var-file="localstack.tfvars" -auto-approve
    } catch {
        Write-Host "Note: Terraform destroy completed with warnings (expected for LocalStack)" -ForegroundColor Yellow
    }
    Pop-Location
    
    # Stop Docker Compose services (only LocalStack container now)
    Write-Host "Stopping LocalStack container..."
    docker-compose down -v
    
    Write-Host "LocalStack cleanup complete" -ForegroundColor Green
}

function Cleanup-AWS {
    Write-Host ""
    Write-Host "Cleaning up AWS resources..." -ForegroundColor Yellow
    
    Push-Location terraform
    
    Write-Host "Destroying Terraform infrastructure..."
    terraform destroy -var-file="environments/aws.tfvars" -auto-approve
    
    Pop-Location
    
    Write-Host "AWS cleanup complete" -ForegroundColor Green
}

try {
    if ($Environment -eq "both" -or $Environment -eq "localstack") {
        Cleanup-LocalStack
    }
    
    if ($Environment -eq "both" -or $Environment -eq "aws") {
        $confirm = Read-Host "Are you sure you want to destroy AWS resources? This cannot be undone. (yes/no)"
        if ($confirm -eq "yes") {
            Cleanup-AWS
        } else {
            Write-Host "AWS cleanup skipped" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Cleanup complete!" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    
} catch {
    Write-Host "Error during cleanup: $_" -ForegroundColor Red
    exit 1
}
