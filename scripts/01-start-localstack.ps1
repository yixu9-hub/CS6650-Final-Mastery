# PowerShell Script: Start LocalStack
# This script starts LocalStack using Docker Compose

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Starting LocalStack..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if Docker is running
try {
    docker info | Out-Null
} catch {
    Write-Host "Error: Docker is not running. Please start Docker first." -ForegroundColor Red
    exit 1
}

# Stop any existing LocalStack containers
Write-Host "Stopping any existing LocalStack containers..." -ForegroundColor Yellow
docker-compose down

# Start LocalStack
Write-Host "Starting LocalStack with Docker Compose..." -ForegroundColor Green
docker-compose up -d localstack

# Wait for LocalStack to be ready
Write-Host "Waiting for LocalStack to be ready..." -ForegroundColor Yellow
$maxAttempts = 30
for ($i = 1; $i -le $maxAttempts; $i++) {
    try {
        $health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -ErrorAction Stop
        if ($health.services.sqs -eq "running" -and $health.services.sns -eq "running") {
            Write-Host "LocalStack is ready!" -ForegroundColor Green
            break
        }
    } catch {
        # Continue waiting
    }
    
    if ($i -eq $maxAttempts) {
        Write-Host "Timeout waiting for LocalStack to start" -ForegroundColor Red
        exit 1
    }
    Write-Host "Waiting... ($i/$maxAttempts)"
    Start-Sleep -Seconds 2
}

# Show LocalStack status
Write-Host ""
Write-Host "LocalStack Status:" -ForegroundColor Cyan
try {
    $health = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health"
    $health | ConvertTo-Json
} catch {
    Write-Host "Failed to get status" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "LocalStack is running!" -ForegroundColor Green
Write-Host "Gateway: http://localhost:4566" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
