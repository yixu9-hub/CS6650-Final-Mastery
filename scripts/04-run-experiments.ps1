# PowerShell Script: Run Experiments
# This script runs all comparison experiments between LocalStack and AWS

param(
    [string]$Environment = "both", # "localstack", "aws", or "both"
    [string]$Experiment = "all",   # "latency", "throughput", "queue", "cost", or "all"
    [int]$Duration = 300           # Duration in seconds for throughput test
)

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Running Experiments: $Experiment on $Environment" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$ErrorActionPreference = "Stop"

function Test-Latency {
    param([string]$BaseUrl, [string]$Env)
    
    Write-Host ""
    Write-Host "Running API Latency Test on $Env..." -ForegroundColor Green
    Write-Host "  Measuring: Client → Receiver (202 Accepted response)" -ForegroundColor Gray
    Write-Host "  This does NOT include queue wait or processing time" -ForegroundColor Gray
    Write-Host ""
    
    $results = @()
    $iterations = 100
    
    for ($i = 1; $i -le $iterations; $i++) {
        $orderId = "latency-test-$Env-$i"
        $payload = @{
            order_id = $orderId
            customer_id = $i
            items = @(
                @{
                    product_id = "product-1"
                    quantity = 1
                    price = 10.0
                }
            )
            created_at = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
        } | ConvertTo-Json
        
        $startTime = Get-Date
        try {
            $response = Invoke-RestMethod -Uri "$BaseUrl/orders/async" -Method Post -Body $payload -ContentType "application/json" -TimeoutSec 10
            $endTime = Get-Date
            $latency = ($endTime - $startTime).TotalMilliseconds
            
            $results += [PSCustomObject]@{
                OrderID = $orderId
                Latency = $latency
                Success = $true
            }
            
            if ($i % 10 -eq 0) {
                Write-Host "  Completed $i/$iterations requests..." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  Request failed: $_" -ForegroundColor Red
            $results += [PSCustomObject]@{
                OrderID = $orderId
                Latency = 0
                Success = $false
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    # Calculate statistics
    $successResults = $results | Where-Object { $_.Success }
    $avgLatency = ($successResults | Measure-Object -Property Latency -Average).Average
    $minLatency = ($successResults | Measure-Object -Property Latency -Minimum).Minimum
    $maxLatency = ($successResults | Measure-Object -Property Latency -Maximum).Maximum
    $p50 = ($successResults | Sort-Object Latency)[([math]::Floor($successResults.Count * 0.5))]
    $p95 = ($successResults | Sort-Object Latency)[([math]::Floor($successResults.Count * 0.95))]
    $p99 = ($successResults | Sort-Object Latency)[([math]::Floor($successResults.Count * 0.99))]
    
    Write-Host ""
    Write-Host "API Latency Results for $Env (Client → Receiver)" -ForegroundColor Cyan
    Write-Host "  Success Rate: $($successResults.Count)/$iterations" -ForegroundColor White
    Write-Host "  Average: $([math]::Round($avgLatency, 2))ms" -ForegroundColor White
    Write-Host "  Min: $([math]::Round($minLatency, 2))ms" -ForegroundColor White
    Write-Host "  Max: $([math]::Round($maxLatency, 2))ms" -ForegroundColor White
    Write-Host "  P50: $([math]::Round($p50.Latency, 2))ms" -ForegroundColor White
    Write-Host "  P95: $([math]::Round($p95.Latency, 2))ms" -ForegroundColor White
    Write-Host "  P99: $([math]::Round($p99.Latency, 2))ms" -ForegroundColor White
    
    # Save results
    $outputFile = "./results/$Env/latency_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $results | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "  Results saved to: $outputFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Note: This only measures API response time. For end-to-end latency:" -ForegroundColor Yellow
    Write-Host "        Wait for messages to be processed, then run:" -ForegroundColor Yellow
    Write-Host "        .\scripts\analyze-latency-stages.ps1 -Environment $Env" -ForegroundColor White
}

function Test-QueueBehavior {
    param([string]$BaseUrl, [string]$Env)
    
    Write-Host ""
    Write-Host "Running Queue Behavior Test on $Env..." -ForegroundColor Green
    
    # Test 1: Visibility Timeout
    Write-Host "  Test 1: Visibility Timeout Behavior" -ForegroundColor Yellow
    Write-Host "    Sending test message..."
    $orderId = "visibility-test-$Env-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $payload = @{
        order_id = $orderId
        customer_id = 999
        items = @(@{ product_id = "test"; quantity = 1; price = 1.0 })
        created_at = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
    } | ConvertTo-Json
    
    Invoke-RestMethod -Uri "$BaseUrl/orders/async" -Method Post -Body $payload -ContentType "application/json" | Out-Null
    Write-Host "    Message sent. Check processor logs for visibility timeout behavior." -ForegroundColor White
    
    # Test 2: Message Retention
    Write-Host ""
    Write-Host "  Test 2: Message Retention (10 minute test)" -ForegroundColor Yellow
    Write-Host "    Stop the processor and wait 10 minutes to verify message retention..." -ForegroundColor White
    Write-Host "    Command: docker-compose stop processor-$Env" -ForegroundColor Gray
    
    # Test 3: Long Polling
    Write-Host ""
    Write-Host "  Test 3: Long Polling Behavior" -ForegroundColor Yellow
    Write-Host "    Empty queue - processor should wait up to 20 seconds for messages" -ForegroundColor White
    Write-Host "    Monitor processor logs to verify long polling wait time" -ForegroundColor White
    
    Write-Host ""
    Write-Host "Queue behavior tests initiated. Monitor logs for results." -ForegroundColor Green
}

# Main execution
try {
    # Determine which environments to test
    $envList = @()
    if ($Environment -eq "both") {
        $envList = @("localstack", "aws")
    } else {
        $envList = @($Environment)
    }
    
    foreach ($env in $envList) {
        # Determine base URL
        $baseUrl = if ($env -eq "localstack") { "http://localhost:8080" } else { Read-Host "Enter AWS ALB URL (e.g., http://alb-xxx.us-west-2.elb.amazonaws.com)" }
        
        Write-Host ""
        Write-Host "Testing environment: $env" -ForegroundColor Cyan
        Write-Host "Base URL: $baseUrl" -ForegroundColor White
        
        # Run experiments
        if ($Experiment -eq "all" -or $Experiment -eq "latency") {
            Test-Latency -BaseUrl $baseUrl -Env $env
        }
        
        if ($Experiment -eq "all" -or $Experiment -eq "queue") {
            Test-QueueBehavior -BaseUrl $baseUrl -Env $env
        }
        
        if ($Experiment -eq "all" -or $Experiment -eq "throughput") {
            Write-Host ""
            Write-Host "For throughput testing, use Locust:" -ForegroundColor Yellow
            Write-Host "  python -m locust -f locustfile/locust_async.py --host=$baseUrl --users=100 --spawn-rate=10" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "Experiments completed!" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Cyan
    
    # Auto-analyze if latency test was run
    if ($Experiment -eq "all" -or $Experiment -eq "latency") {
        Write-Host ""
        Write-Host "Analyzing latency stages..." -ForegroundColor Cyan
        Write-Host ""
        Write-Host "NOTE: API latency test measures client → receiver response time." -ForegroundColor Yellow
        Write-Host "      For end-to-end latency analysis (including queue and processing):" -ForegroundColor Yellow
        Write-Host "      Run: .\scripts\analyze-latency-stages.ps1" -ForegroundColor White
        Write-Host ""
        Write-Host "      This requires processor metrics files in src/processor/metrics/" -ForegroundColor Gray
        Write-Host "      which are generated when processor processes messages." -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Review API latency results in ./results/ directory" -ForegroundColor White
    Write-Host "  2. Analyze processor metrics: .\scripts\analyze-latency-stages.ps1" -ForegroundColor White
    Write-Host "  3. Run Python analysis: python analysis/analyze.py" -ForegroundColor White
    Write-Host "  4. Generate visualizations: python analysis/visualize.py" -ForegroundColor White
    
} catch {
    Write-Host "Error during experiments: $_" -ForegroundColor Red
    exit 1
}
