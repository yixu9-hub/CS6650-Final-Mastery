#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Throughput stress test - gradually increase load to find system limits
.DESCRIPTION
    Uses Locust to progressively increase load on the order system.
    Monitors queue depth, response times, and error rates to find bottlenecks and breaking points.
.PARAMETER Environment
    Target environment: localstack or aws
.PARAMETER StartUsers
    Initial number of concurrent users (default: 10)
.PARAMETER MaxUsers
    Maximum number of concurrent users (default: 200)
.PARAMETER StepSize
    Number of users to add per step (default: 20)
.PARAMETER StepDuration
    Duration of each load step in seconds (default: 60)
.PARAMETER SpawnRate
    Rate of spawning users per second (default: 5)
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("localstack", "aws")]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [int]$StartUsers = 10,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxUsers = 200,
    
    [Parameter(Mandatory=$false)]
    [int]$StepSize = 20,
    
    [Parameter(Mandatory=$false)]
    [int]$StepDuration = 60,
    
    [Parameter(Mandatory=$false)]
    [int]$SpawnRate = 5
)

$ErrorActionPreference = "Stop"

# Configuration
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$resultsDir = ".\results\$Environment\stress_test_$timestamp"
$locustFile = ".\locustfile\locust_async.py"

# Create results directory
New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "Throughput Stress Test - $Environment Environment" -ForegroundColor Yellow
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Configuration:" -ForegroundColor White
Write-Host "  • Start Users:    $StartUsers" -ForegroundColor Gray
Write-Host "  • Max Users:      $MaxUsers" -ForegroundColor Gray
Write-Host "  • Step Size:      $StepSize users" -ForegroundColor Gray
Write-Host "  • Step Duration:  $StepDuration seconds" -ForegroundColor Gray
Write-Host "  • Spawn Rate:     $SpawnRate users/sec" -ForegroundColor Gray
Write-Host "  • Results Dir:    $resultsDir" -ForegroundColor Gray
Write-Host "================================================================`n" -ForegroundColor Cyan

# Get target URL and queue configuration
if ($Environment -eq "localstack") {
    $targetUrl = "http://localhost:8080"
    $queueUrl = "http://sqs.us-west-2.localhost.localstack.cloud:4566/000000000000/order-processing-queue-localstack"
    $env:AWS_ENDPOINT_URL = "http://localhost:4566"
    $region = "us-west-2"
    
    Write-Host "Checking LocalStack availability..." -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -ErrorAction Stop
        Write-Host "✓ LocalStack is running" -ForegroundColor Green
    } catch {
        Write-Host "✗ LocalStack is not accessible at http://localhost:4566" -ForegroundColor Red
        Write-Host "  Please start LocalStack first: docker-compose up -d localstack" -ForegroundColor Yellow
        exit 1
    }
} else {
    # AWS configuration - get from AWS directly
    $region = "us-west-2"
    
    # Get ALB DNS from AWS
    $albDns = aws elbv2 describe-load-balancers --region $region --names ordersystem-alb --query 'LoadBalancers[0].DNSName' --output text 2>$null
    if (-not $albDns -or $albDns -eq "None") {
        Write-Host "✗ Cannot get ALB DNS name from AWS" -ForegroundColor Red
        exit 1
    }
    
    $targetUrl = "http://$albDns"
    
    # Get Queue URL from AWS
    $queueUrl = aws sqs list-queues --region $region --queue-name-prefix order-processing-queue --query 'QueueUrls[0]' --output text 2>$null
    if (-not $queueUrl -or $queueUrl -eq "None") {
        Write-Host "✗ Cannot get SQS Queue URL from AWS" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "AWS Target: $targetUrl" -ForegroundColor Cyan
    Write-Host "Queue URL: $queueUrl" -ForegroundColor Gray
}

# Initialize metrics file
$metricsFile = "$resultsDir\stress_metrics.csv"
"Timestamp,Users,QueueDepth,QueueVisible,QueueProcessing,RPS,AvgResponseTime,P95ResponseTime,ErrorRate,TotalRequests,TotalFailures" | Out-File -FilePath $metricsFile -Encoding UTF8

# Function to get queue metrics
function Get-QueueMetrics {
    try {
        $attrs = aws sqs get-queue-attributes `
            --queue-url $queueUrl `
            --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible `
            --region $region `
            --output json 2>$null | ConvertFrom-Json
        
        if ($attrs) {
            $visible = [int]$attrs.Attributes.ApproximateNumberOfMessages
            $notVisible = [int]$attrs.Attributes.ApproximateNumberOfMessagesNotVisible
            return @{
                Total = $visible + $notVisible
                Visible = $visible
                Processing = $notVisible
            }
        }
    } catch {
        Write-Host "Warning: Failed to get queue metrics" -ForegroundColor Yellow
    }
    return @{ Total = 0; Visible = 0; Processing = 0 }
}

# Function to monitor system during load step
function Monitor-LoadStep {
    param(
        [int]$CurrentUsers,
        [int]$DurationSeconds,
        [string]$StepName
    )
    
    Write-Host "`n--- $StepName (Users: $CurrentUsers) ---" -ForegroundColor Yellow
    
    $startTime = Get-Date
    $endTime = $startTime.AddSeconds($DurationSeconds)
    $sampleInterval = 5  # Sample every 5 seconds
    
    $maxQueue = 0
    $avgQueue = @()
    
    while ((Get-Date) -lt $endTime) {
        $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 0)
        $remaining = [math]::Round(($endTime - (Get-Date)).TotalSeconds, 0)
        
        # Get queue metrics
        $queue = Get-QueueMetrics
        $avgQueue += $queue.Total
        if ($queue.Total -gt $maxQueue) { $maxQueue = $queue.Total }
        
        # Display current status
        Write-Host "[$elapsed/$DurationSeconds s] Queue: $($queue.Total) (Visible: $($queue.Visible), Processing: $($queue.Processing)) | Remaining: $remaining s" -ForegroundColor Gray
        
        Start-Sleep -Seconds $sampleInterval
    }
    
    $avgQueueDepth = if ($avgQueue.Count -gt 0) { [math]::Round(($avgQueue | Measure-Object -Average).Average, 1) } else { 0 }
    
    return @{
        MaxQueue = $maxQueue
        AvgQueue = $avgQueueDepth
    }
}

# Start Locust in headless mode with progressive load
Write-Host "`nStarting Locust stress test...`n" -ForegroundColor Cyan

$locustProcess = $null
$currentUsers = $StartUsers
$stepNumber = 1

try {
    # Calculate total steps
    $totalSteps = [math]::Ceiling(($MaxUsers - $StartUsers) / $StepSize) + 1
    
    Write-Host "Test will run $totalSteps load steps from $StartUsers to $MaxUsers users`n" -ForegroundColor White
    
    # Purge queue before starting
    Write-Host "Purging SQS queue..." -ForegroundColor Yellow
    aws sqs purge-queue --queue-url $queueUrl --region $region 2>&1 | Out-Null
    Start-Sleep -Seconds 3
    
    # Run each load step
    while ($currentUsers -le $MaxUsers) {
        $stepName = "Step $stepNumber/$totalSteps"
        
        Write-Host "`n================================================================" -ForegroundColor Cyan
        Write-Host "$stepName - Ramping to $currentUsers users" -ForegroundColor Yellow
        Write-Host "================================================================" -ForegroundColor Cyan
        
        # Start or update Locust
        if ($null -eq $locustProcess) {
            Write-Host "Starting Locust with $currentUsers users..." -ForegroundColor White
            
            $locustArgs = @(
                "-f", $locustFile,
                "--headless",
                "--host=$targetUrl",
                "--users=$currentUsers",
                "--spawn-rate=$SpawnRate",
                "--run-time=$($StepDuration)s",
                "--csv=$resultsDir\locust_step_$stepNumber",
                "--html=$resultsDir\locust_step_$stepNumber.html"
            )
            
            $locustProcess = Start-Process -FilePath "locust" -ArgumentList $locustArgs -NoNewWindow -PassThru
            
            # Wait for ramp-up
            $rampUpTime = [math]::Ceiling($currentUsers / $SpawnRate)
            Write-Host "Ramping up $currentUsers users at $SpawnRate users/sec (ETA: $rampUpTime seconds)..." -ForegroundColor Gray
            Start-Sleep -Seconds $rampUpTime
        }
        
        # Monitor this load step
        $stepMetrics = Monitor-LoadStep -CurrentUsers $currentUsers -DurationSeconds $StepDuration -StepName $stepName
        
        # Wait for Locust to finish this step
        Write-Host "`nWaiting for Locust to complete step..." -ForegroundColor Gray
        Wait-Process -Id $locustProcess.Id -ErrorAction SilentlyContinue
        $locustProcess = $null
        
        # Parse Locust stats
        $statsFile = "$resultsDir\locust_step_$($stepNumber)_stats.csv"
        if (Test-Path $statsFile) {
            $stats = Import-Csv $statsFile | Where-Object { $_.Name -eq "Aggregated" }
            if ($stats) {
                $rps = [math]::Round([double]$stats.'Requests/s', 2)
                $avgResponse = [math]::Round([double]$stats.'Average Response Time', 0)
                $p95Response = [math]::Round([double]$stats.'95%', 0)
                $totalReqs = [int]$stats.'Request Count'
                $failures = [int]$stats.'Failure Count'
                $errorRate = if ($totalReqs -gt 0) { [math]::Round(($failures / $totalReqs) * 100, 2) } else { 0 }
                
                # Get final queue depth
                $finalQueue = Get-QueueMetrics
                
                # Save metrics
                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "$timestamp,$currentUsers,$($finalQueue.Total),$($finalQueue.Visible),$($finalQueue.Processing),$rps,$avgResponse,$p95Response,$errorRate,$totalReqs,$failures" | 
                    Out-File -FilePath $metricsFile -Append -Encoding UTF8
                
                # Display step summary
                Write-Host "`n--- Step $stepNumber Summary ---" -ForegroundColor Green
                Write-Host "Users:            $currentUsers" -ForegroundColor White
                Write-Host "RPS:              $rps req/s" -ForegroundColor White
                Write-Host "Avg Response:     $avgResponse ms" -ForegroundColor White
                Write-Host "P95 Response:     $p95Response ms" -ForegroundColor White
                Write-Host "Error Rate:       $errorRate%" -ForegroundColor $(if ($errorRate -gt 5) { "Red" } else { "White" })
                Write-Host "Queue (Avg/Max):  $($stepMetrics.AvgQueue) / $($stepMetrics.MaxQueue)" -ForegroundColor White
                Write-Host "Total Requests:   $totalReqs" -ForegroundColor Gray
                Write-Host "Total Failures:   $failures" -ForegroundColor $(if ($failures -gt 0) { "Yellow" } else { "Gray" })
                
                # Check if system is overloaded
                if ($errorRate -gt 10) {
                    Write-Host "`n⚠ WARNING: Error rate exceeds 10% - System may be overloaded!" -ForegroundColor Red
                }
                if ($stepMetrics.MaxQueue -gt 1000) {
                    Write-Host "⚠ WARNING: Queue depth exceeded 1000 - Processing backlog detected!" -ForegroundColor Red
                }
            }
        }
        
        # Prepare for next step
        $currentUsers += $StepSize
        $stepNumber++
        
        # Wait for queue to drain before next step
        if ($currentUsers -le $MaxUsers) {
            Write-Host "`nWaiting 30 seconds before next step..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
    }
    
    Write-Host "`n================================================================" -ForegroundColor Cyan
    Write-Host "Stress Test Completed!" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "Results saved to: $resultsDir" -ForegroundColor White
    
    # Generate summary report
    Write-Host "`nGenerating summary report..." -ForegroundColor Cyan
    $metrics = Import-Csv $metricsFile
    
    $summaryFile = "$resultsDir\summary.txt"
    @"
Throughput Stress Test Summary
Environment: $Environment
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Test Configuration:
- Start Users: $StartUsers
- Max Users: $MaxUsers
- Step Size: $StepSize
- Step Duration: $StepDuration seconds
- Total Steps: $totalSteps

Performance Metrics:
"@ | Out-File -FilePath $summaryFile -Encoding UTF8
    
    $metrics | ForEach-Object {
        @"
  
Step @ $($_.Users) users:
  - RPS: $($_.RPS)
  - Avg Response Time: $($_.AvgResponseTime) ms
  - P95 Response Time: $($_.P95ResponseTime) ms
  - Error Rate: $($_.ErrorRate)%
  - Max Queue Depth: $($_.QueueDepth)
  - Total Requests: $($_.TotalRequests)
  - Total Failures: $($_.TotalFailures)
"@ | Out-File -FilePath $summaryFile -Append -Encoding UTF8
    }
    
    Write-Host "✓ Summary saved to: $summaryFile" -ForegroundColor Green
    
} catch {
    Write-Host "`n✗ Error during stress test: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
} finally {
    # Cleanup
    if ($null -ne $locustProcess -and -not $locustProcess.HasExited) {
        Write-Host "`nStopping Locust..." -ForegroundColor Yellow
        Stop-Process -Id $locustProcess.Id -Force -ErrorAction SilentlyContinue
    }
    
    if ($Environment -eq "localstack") {
        $env:AWS_ENDPOINT_URL = ""
    }
}

Write-Host "`nStress test complete. Check results in: $resultsDir`n" -ForegroundColor Cyan
