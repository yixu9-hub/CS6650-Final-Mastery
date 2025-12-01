<#
.SYNOPSIS
    Run complete end-to-end latency experiment with automatic analysis
    
.DESCRIPTION
    This script runs a comprehensive latency experiment that:
    1. Sends test orders via API (measures API latency)
    2. Waits for processor to process all messages
    3. Collects processor metrics
    4. Runs full latency stage analysis
    5. Generates comparison report
    
.PARAMETER Environment
    The environment to test: 'localstack', 'aws', or 'both' (default: 'both')
    
.PARAMETER NumOrders
    Number of test orders to send (default: 100)
    
.PARAMETER SkipSend
    Skip sending new orders, only analyze existing metrics

.EXAMPLE
    .\scripts\05-run-full-latency-experiment.ps1
    Run full experiment on both environments
    
.EXAMPLE
    .\scripts\05-run-full-latency-experiment.ps1 -Environment localstack -NumOrders 50
    Run experiment on LocalStack with 50 orders
    
.EXAMPLE
    .\scripts\05-run-full-latency-experiment.ps1 -SkipSend
    Skip sending, only analyze existing metrics
#>

param(
    [string]$Environment = "both",
    [int]$NumOrders = 100,
    [switch]$SkipSend
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "FULL END-TO-END LATENCY EXPERIMENT" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

function Get-QueueDepth {
    param([string]$QueueUrl, [string]$Env)
    
    try {
        if ($Env -eq "localstack") {
            $result = aws sqs get-queue-attributes `
                --queue-url $QueueUrl `
                --endpoint-url http://localhost:4566 `
                --attribute-names ApproximateNumberOfMessages `
                --output json 2>$null | ConvertFrom-Json
        } else {
            $result = aws sqs get-queue-attributes `
                --queue-url $QueueUrl `
                --attribute-names ApproximateNumberOfMessages `
                --region us-west-2 `
                --output json 2>$null | ConvertFrom-Json
        }
        
        if ($result.Attributes) {
            return [int]$result.Attributes.ApproximateNumberOfMessages
        }
        return 0
    } catch {
        $errorMsg = $_.Exception.Message
        Write-Host "    Warning: Could not get queue depth: $errorMsg" -ForegroundColor Yellow
        return -1
    }
}

function Send-TestOrders {
    param([string]$BaseUrl, [string]$Env, [int]$Count)
    
    Write-Host ""
    Write-Host "Step 1: Sending $Count test orders to $Env..." -ForegroundColor Green
    Write-Host "  API Endpoint: $BaseUrl/orders/async" -ForegroundColor Gray
    Write-Host ""
    
    $results = @()
    $startTime = Get-Date
    
    for ($i = 1; $i -le $Count; $i++) {
        $orderId = "e2e-test-$Env-$(Get-Date -Format 'yyyyMMddHHmmss')-$i"
        $payload = @{
            order_id = $orderId
            customer_id = $i
            items = @(
                @{
                    product_id = "product-test"
                    quantity = 1
                    price = 10.0
                }
            )
            created_at = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json
        
        $apiStart = Get-Date
        try {
            $response = Invoke-RestMethod -Uri "$BaseUrl/orders/async" `
                -Method Post -Body $payload -ContentType "application/json" `
                -TimeoutSec 10
            $apiLatency = (Get-Date) - $apiStart
            
            $results += [PSCustomObject]@{
                OrderID = $orderId
                APILatency = $apiLatency.TotalMilliseconds
                Success = $true
                Timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            }
            
            if ($i % 10 -eq 0) {
                Write-Host "  Progress: $i/$Count orders sent..." -ForegroundColor Yellow
            }
        } catch {
            $errorMsg = $_.Exception.Message
            Write-Host "  Error sending order $i`: $errorMsg" -ForegroundColor Red
            $results += [PSCustomObject]@{
                OrderID = $orderId
                APILatency = 0
                Success = $false
                Timestamp = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
            }
        }
        
        Start-Sleep -Milliseconds 50
    }
    
    $totalTime = (Get-Date) - $startTime
    $successCount = ($results | Where-Object { $_.Success }).Count
    $avgApiLatency = ($results | Where-Object { $_.Success } | Measure-Object -Property APILatency -Average).Average
    
    Write-Host ""
    Write-Host "  Sending completed:" -ForegroundColor Green
    Write-Host "    Total time: $([math]::Round($totalTime.TotalSeconds, 2))s" -ForegroundColor White
    Write-Host "    Success rate: $successCount/$Count" -ForegroundColor White
    Write-Host "    Avg API latency: $([math]::Round($avgApiLatency, 2))ms" -ForegroundColor White
    
    # Save API latency results
    $apiResultFile = "./results/$Env/api_latency_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $results | Export-Csv -Path $apiResultFile -NoTypeInformation
    Write-Host "    Results saved: $apiResultFile" -ForegroundColor Gray
    
    return $results
}

function Wait-ForProcessing {
    param([string]$QueueUrl, [string]$Env, [int]$ExpectedCount)
    
    Write-Host ""
    Write-Host "Step 2: Waiting for processor to handle messages..." -ForegroundColor Green
    Write-Host "  Expected messages: $ExpectedCount" -ForegroundColor Gray
    Write-Host ""
    
    $maxWaitMinutes = 10
    $checkInterval = 10
    $maxChecks = ($maxWaitMinutes * 60) / $checkInterval
    $checksPerformed = 0
    $metricsCollected = $false
    
    Write-Host "  Monitoring queue depth (max wait: ${maxWaitMinutes}m)..." -ForegroundColor Yellow
    
    # Wait a bit for processor to start and generate some metrics
    if ($Env -eq "localstack") {
        Write-Host "  Waiting for processor to start processing..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
    
    while ($checksPerformed -lt $maxChecks) {
        $depth = Get-QueueDepth -QueueUrl $QueueUrl -Env $Env
        
        # For LocalStack, collect metrics after first check (processor should be active)
        if ($Env -eq "localstack" -and -not $metricsCollected -and $checksPerformed -eq 0 -and $depth -lt $ExpectedCount) {
            Write-Host "  Collecting metrics while processor is active (queue: $depth remaining)..." -ForegroundColor Cyan
            Copy-ProcessorMetrics -Env $Env
            $metricsCollected = $true
        }
        
        if ($depth -eq 0) {
            Write-Host "  ✓ Queue is empty - all messages processed!" -ForegroundColor Green
            Start-Sleep -Seconds 5  # Wait a bit more for metrics to be written
            return $true
        } elseif ($depth -gt 0) {
            Write-Host "  Queue depth: $depth messages remaining..." -ForegroundColor Yellow
        }
        
        $checksPerformed++
        Start-Sleep -Seconds $checkInterval
    }
    
    Write-Host "  Warning: Timeout waiting for queue to empty" -ForegroundColor Yellow
    Write-Host "  Proceeding with analysis of available metrics..." -ForegroundColor Yellow
    return $false
}

function Copy-ProcessorMetrics {
    param([string]$Env)
    
    Write-Host ""
    Write-Host "Step 3: Collecting processor metrics from $Env..." -ForegroundColor Green
    
    if ($Env -eq "localstack") {
        # Find processor container (LocalStack ECS containers have "order-processor" in the image name)
        $containers = docker ps --format "{{.Names}}`t{{.Image}}" | Out-String
        $processorContainer = $containers -split "`n" | Where-Object { $_ -match "order-processor:latest" } | ForEach-Object { ($_ -split "`t")[0] } | Select-Object -First 1
        
        if ($processorContainer) {
            Write-Host "  Found processor container: $processorContainer" -ForegroundColor Gray
            
            # Create temp directory
            $tempDir = "./temp_metrics"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Copy metrics from active container
            Write-Host "  Copying metrics from active container..." -ForegroundColor Gray
            docker cp "${processorContainer}:/app/metrics/." $tempDir 2>$null
        
            # Move to processor metrics directory
            $metricsFiles = Get-ChildItem $tempDir -Filter "metrics_*.csv" -ErrorAction SilentlyContinue
            if ($metricsFiles.Count -gt 0) {
                foreach ($file in $metricsFiles) {
                    $destFile = "src/processor/metrics/$($file.Name)"
                    Copy-Item $file.FullName $destFile -Force
                    Write-Host "  Collected: $($file.Name)" -ForegroundColor Gray
                }
                Write-Host "  ✓ Metrics collected from active container" -ForegroundColor Green
            } else {
                Write-Host "  Warning: No metrics files found in container" -ForegroundColor Yellow
            }
            
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "  AWS metrics are stored in container volumes" -ForegroundColor Gray
            Write-Host "  Note: You may need to manually retrieve metrics from ECS tasks" -ForegroundColor Yellow
            Write-Host "  Or wait for processor to restart/shutdown to flush metrics" -ForegroundColor Yellow
        }
    }
}

function Invoke-LatencyAnalysis {
    param([string]$Env)
    
    Write-Host ""
    Write-Host "Step 4: Running latency stage analysis for $Env..." -ForegroundColor Green
    Write-Host ""
    
    if (Test-Path ".\scripts\analyze-latency-stages.ps1") {
        & ".\scripts\analyze-latency-stages.ps1" -Environment $Env
    } else {
        Write-Host "  Warning: analyze-latency-stages.ps1 not found" -ForegroundColor Yellow
    }
}

# Main execution
try {
    $environments = @()
    if ($Environment -eq "both") {
        $environments = @("localstack", "aws")
    } else {
        $environments = @($Environment)
    }
    
    foreach ($env in $environments) {
        Write-Host ""
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host "TESTING ENVIRONMENT: $($env.ToUpper())" -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor Cyan
        
        # Determine configuration
        if ($env -eq "localstack") {
            $baseUrl = "http://localhost:8080"
            $queueUrl = "http://localhost:4566/000000000000/order-queue"
        } else {
            $baseUrl = Read-Host "Enter AWS ALB URL (e.g., http://alb-xxx.us-west-2.elb.amazonaws.com)"
            $queueUrl = Read-Host "Enter AWS SQS Queue URL"
        }
        
        Write-Host "  Base URL: $baseUrl" -ForegroundColor White
        Write-Host "  Queue URL: $queueUrl" -ForegroundColor White
        
        # Step 1: Send orders (unless skipped)
        if (-not $SkipSend) {
            $sendResults = Send-TestOrders -BaseUrl $baseUrl -Env $env -Count $NumOrders
            $successCount = ($sendResults | Where-Object { $_.Success }).Count
            
            if ($successCount -eq 0) {
                Write-Host ""
                Write-Host "Error: No orders were successfully sent. Skipping this environment." -ForegroundColor Red
                continue
            }
            
            # Step 2: Wait for processing (LocalStack metrics collected during this step)
            Wait-ForProcessing -QueueUrl $queueUrl -Env $env -ExpectedCount $successCount | Out-Null
        } else {
            Write-Host ""
            Write-Host "Step 1-2: Skipped (using existing data)" -ForegroundColor Yellow
        }
        
        # Step 3: Collect metrics (AWS only, LocalStack already collected during step 2)
        if ($env -eq "aws") {
            Write-Host ""
            Write-Host "Step 3: AWS metrics collection..." -ForegroundColor Green
            Write-Host "  AWS metrics are stored in CloudWatch Logs" -ForegroundColor Gray
            Write-Host "  Use CloudWatch Insights to query processor metrics" -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "Step 3: LocalStack metrics already collected" -ForegroundColor Green
        }
        
        # Step 4: Run analysis
        Invoke-LatencyAnalysis -Env $env
    }
    
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "EXPERIMENT COMPLETED!" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Results available in:" -ForegroundColor Cyan
    Write-Host "  • API latency: ./results/{environment}/api_latency_*.csv" -ForegroundColor White
    Write-Host "  • Processor metrics: ./src/processor/metrics/metrics_*.csv" -ForegroundColor White
    Write-Host ""
    Write-Host "To re-run analysis only:" -ForegroundColor Cyan
    Write-Host "  .\scripts\analyze-latency-stages.ps1" -ForegroundColor White
    Write-Host ""
    
} catch {
    Write-Host ""
    $errorMsg = $_.Exception.Message
    Write-Host "Error during experiment: $errorMsg" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
