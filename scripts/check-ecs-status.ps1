# PowerShell Script: Check ECS Status
# This script helps you view the status of ECS services in LocalStack or AWS

param(
    [string]$Environment = "localstack" # "localstack" or "aws"
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking ECS Status for: $Environment" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

if ($Environment -eq "localstack") {
    $endpoint = "http://localhost:4566"
    $region = "us-west-2"
    
    Write-Host ""
    Write-Host "LocalStack ECS Services:" -ForegroundColor Yellow
    Write-Host ""
    
    # List ECS services
    Write-Host "Listing ECS services..." -ForegroundColor Cyan
    aws ecs list-services --cluster ordersystem-cluster --endpoint-url $endpoint --region $region
    
    Write-Host ""
    Write-Host "Docker containers (including ECS tasks):" -ForegroundColor Cyan
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    Write-Host ""
    Write-Host "To view logs of an ECS container:" -ForegroundColor Yellow
    Write-Host "  docker logs -f <container-name>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host "  docker logs -f $(docker ps --filter 'name=ls-ecs-ordersystem' --format '{{.Names}}' | Select-Object -First 1)" -ForegroundColor Gray
    
} else {
    Write-Host ""
    Write-Host "AWS ECS Services:" -ForegroundColor Yellow
    Write-Host ""
    
    # List ECS services
    Write-Host "Listing ECS services..." -ForegroundColor Cyan
    aws ecs list-services --cluster ordersystem-cluster --region us-west-2
    
    Write-Host ""
    Write-Host "Get service details:" -ForegroundColor Cyan
    aws ecs describe-services --cluster ordersystem-cluster --services order-receiver-svc order-processor-svc --region us-west-2
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Status check complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
