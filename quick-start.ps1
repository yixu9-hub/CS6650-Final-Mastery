# Quick Start Script for LocalStack Experiments
# This script helps you get started with the LocalStack vs AWS comparison experiments

Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     CS6650 Final Mastery - LocalStack vs AWS Experiments     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

Write-Host ""
Write-Host "This script will help you set up and run comparison experiments" -ForegroundColor White
Write-Host "between LocalStack and AWS for the order processing system." -ForegroundColor White
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$prerequisites = @{
    "Docker" = { docker --version }
    "Terraform" = { terraform --version }
    "AWS CLI" = { aws --version }
    "Python" = { python --version }
    "Go" = { go version }
}

$missingPrereqs = @()

foreach ($name in $prerequisites.Keys) {
    try {
        $null = & $prerequisites[$name] 2>&1
        Write-Host "  ✓ $name installed" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ $name not found" -ForegroundColor Red
        $missingPrereqs += $name
    }
}

if ($missingPrereqs.Count -gt 0) {
    Write-Host ""
    Write-Host "Missing prerequisites: $($missingPrereqs -join ', ')" -ForegroundColor Red
    Write-Host "Please install them before continuing." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "All prerequisites installed! ✓" -ForegroundColor Green
Write-Host ""

# Main menu
while ($true) {
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "What would you like to do?" -ForegroundColor White
    Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Setup LocalStack environment" -ForegroundColor White
    Write-Host "2. Deploy to LocalStack" -ForegroundColor White
    Write-Host "3. Deploy to AWS" -ForegroundColor White
    Write-Host "4. Run experiments (latency test)" -ForegroundColor White
    Write-Host "5. Run load test with Locust" -ForegroundColor White
    Write-Host "6. Analyze results" -ForegroundColor White
    Write-Host "7. Generate visualizations" -ForegroundColor White
    Write-Host "8. View experiment README" -ForegroundColor White
    Write-Host "9. Cleanup resources" -ForegroundColor White
    Write-Host "0. Exit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Enter your choice (0-9)"
    
    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Host "Starting LocalStack..." -ForegroundColor Cyan
            .\scripts\01-start-localstack.ps1
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            Write-Host ""
            Write-Host "Deploying to LocalStack..." -ForegroundColor Cyan
            Write-Host "Note: This deploys ECS services via Terraform (not Docker Compose)" -ForegroundColor Yellow
            Write-Host ""
            .\scripts\deploy-localstack.ps1
            Write-Host ""
            Write-Host "LocalStack API: http://localhost:8080" -ForegroundColor Green
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            Write-Host ""
            Write-Host "Deploying to AWS..." -ForegroundColor Cyan
            Write-Host ""
            $confirm = Read-Host "This will create real AWS resources (~$80/month). Continue? (yes/no)"
            if ($confirm -eq "yes") {
                Write-Host ""
                Write-Host "Step 1: Pushing Docker images to ECR..." -ForegroundColor Yellow
                .\scripts\push-images-to-ecr.ps1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host ""
                    Write-Host "Step 2: Deploying infrastructure with Terraform..." -ForegroundColor Yellow
                    .\scripts\deploy-aws.ps1
                    
                    Write-Host ""
                    Write-Host "AWS Deployment complete!" -ForegroundColor Green
                    Write-Host "Get ALB DNS: cd infra; terraform output alb_dns_name" -ForegroundColor Cyan
                } else {
                    Write-Host "Failed to push images to ECR. Please check AWS credentials." -ForegroundColor Red
                }
            } else {
                Write-Host "AWS deployment cancelled." -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Write-Host ""
            Write-Host "Running latency experiments..." -ForegroundColor Cyan
            .\scripts\04-run-experiments.ps1 -Experiment latency
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Write-Host ""
            Write-Host "Starting Locust for load testing..." -ForegroundColor Cyan
            Write-Host "Locust web UI will open at http://localhost:8089" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Select environment:" -ForegroundColor White
            Write-Host "  L - LocalStack (http://localhost:8080)" -ForegroundColor Gray
            Write-Host "  A - AWS (requires ALB DNS)" -ForegroundColor Gray
            Write-Host ""
            $env = Read-Host "Test LocalStack (L) or AWS (A)?"
            if ($env -eq "L" -or $env -eq "l") {
                Write-Host ""
                Write-Host "Testing LocalStack at http://localhost:8080" -ForegroundColor Cyan
                Write-Host "Recommended: 100 users, spawn rate 10" -ForegroundColor Yellow
                locust -f locustfile/locust_async.py --host=http://localhost:8080
            } else {
                Write-Host ""
                Write-Host "Get ALB DNS with: cd infra; terraform output alb_dns_name" -ForegroundColor Yellow
                $awsHost = Read-Host "Enter AWS ALB DNS (e.g., http://ordersystem-alb-xxx.us-west-2.elb.amazonaws.com)"
                Write-Host ""
                Write-Host "Testing AWS at $awsHost" -ForegroundColor Cyan
                Write-Host "Recommended: 100 users, spawn rate 10" -ForegroundColor Yellow
                locust -f locustfile/locust_async.py --host=$awsHost
            }
        }
        "6" {
            Write-Host ""
            Write-Host "Analyzing results..." -ForegroundColor Cyan
            python analysis/analyze.py
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "7" {
            Write-Host ""
            Write-Host "Generating visualizations..." -ForegroundColor Cyan
            python analysis/visualize.py
            Write-Host ""
            Write-Host "Opening results folder..." -ForegroundColor Yellow
            Start-Process "results"
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "8" {
            Write-Host ""
            if (Test-Path "EXPERIMENT_README.md") {
                Get-Content "EXPERIMENT_README.md" | Write-Host
            } else {
                Write-Host "README not found" -ForegroundColor Red
            }
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "9" {
            Write-Host ""
            Write-Host "Cleanup options:" -ForegroundColor Cyan
            Write-Host "1. LocalStack only" -ForegroundColor White
            Write-Host "2. AWS only" -ForegroundColor White
            Write-Host "3. Both" -ForegroundColor White
            Write-Host "0. Cancel" -ForegroundColor White
            Write-Host ""
            
            $cleanupChoice = Read-Host "Enter your choice"
            switch ($cleanupChoice) {
                "1" { .\scripts\05-cleanup.ps1 -Environment localstack }
                "2" { .\scripts\05-cleanup.ps1 -Environment aws }
                "3" { .\scripts\05-cleanup.ps1 -Environment both }
                default { Write-Host "Cleanup cancelled" -ForegroundColor Yellow }
            }
            Write-Host ""
            Write-Host "Press any key to continue..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "0" {
            Write-Host ""
            Write-Host "Goodbye! 👋" -ForegroundColor Cyan
            exit 0
        }
        default {
            Write-Host ""
            Write-Host "Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
    
    Clear-Host
    Write-Host @"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     CS6650 Final Mastery - LocalStack vs AWS Experiments     ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    Write-Host ""
}
