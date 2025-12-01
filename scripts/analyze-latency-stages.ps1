<#
.SYNOPSIS
    Analyze latency breakdown across different stages of message processing
    
.DESCRIPTION
    This script analyzes the metrics collected by the processor to show latency breakdown:
    1. Queue Latency: Time from order creation to fetching from queue
    2. Processing Latency: Time spent processing the order (payment simulation)
    3. End-to-End Latency: Total time from creation to completion
    
.PARAMETER Environment
    The environment to analyze: 'localstack', 'aws', or 'both' (default: 'both')
    
.PARAMETER MetricsPath
    Path to the metrics CSV files (default: './src/processor/metrics')
    
.PARAMETER OutputFormat
    Output format: 'console' or 'csv' (default: 'console')

.EXAMPLE
    .\scripts\analyze-latency-stages.ps1
    Analyze both environments and display results in console
    
.EXAMPLE
    .\scripts\analyze-latency-stages.ps1 -Environment localstack -OutputFormat csv
    Analyze LocalStack only and save results to CSV
#>

param(
    [string]$Environment = "both",
    [string]$MetricsPath = "./src/processor/metrics",
    [string]$OutputFormat = "console"
)

function Get-LatencyStats {
    param([array]$Values)
    
    if ($Values.Count -eq 0) {
        return @{
            Count = 0
            Mean = 0
            Median = 0
            P50 = 0
            P95 = 0
            P99 = 0
            Min = 0
            Max = 0
            StdDev = 0
        }
    }
    
    $sorted = $Values | Sort-Object
    $count = $sorted.Count
    
    $mean = ($sorted | Measure-Object -Average).Average
    $median = $sorted[[math]::Floor($count / 2)]
    $p50 = $sorted[[math]::Floor($count * 0.50)]
    $p95 = $sorted[[math]::Min([math]::Floor($count * 0.95), $count - 1)]
    $p99 = $sorted[[math]::Min([math]::Floor($count * 0.99), $count - 1)]
    $min = $sorted[0]
    $max = $sorted[-1]
    
    # Calculate standard deviation
    $variance = ($sorted | ForEach-Object { [math]::Pow($_ - $mean, 2) } | Measure-Object -Sum).Sum / $count
    $stdDev = [math]::Sqrt($variance)
    
    return @{
        Count = $count
        Mean = [math]::Round($mean, 2)
        Median = [math]::Round($median, 2)
        P50 = [math]::Round($sorted[$p50], 2)
        P95 = [math]::Round($sorted[$p95], 2)
        P99 = [math]::Round($sorted[$p99], 2)
        Min = [math]::Round($min, 2)
        Max = [math]::Round($max, 2)
        StdDev = [math]::Round($stdDev, 2)
    }
}

function Analyze-MetricsFile {
    param(
        [string]$FilePath,
        [string]$Env
    )
    
    Write-Host "`nAnalyzing: $FilePath" -ForegroundColor Cyan
    
    $data = Import-Csv $FilePath
    
    if ($data.Count -eq 0) {
        Write-Host "  No data found in file" -ForegroundColor Yellow
        return $null
    }
    
    # Group by event type
    $fetched = $data | Where-Object { $_.event_type -eq "fetched" }
    $processed = $data | Where-Object { $_.event_type -eq "processed" }
    $completed = $data | Where-Object { $_.event_type -eq "completed" }
    
    Write-Host "  Total Events: $($data.Count)" -ForegroundColor Green
    Write-Host "    - Fetched: $($fetched.Count)"
    Write-Host "    - Processed: $($processed.Count)"
    Write-Host "    - Completed: $($completed.Count)"
    
    # Calculate latency statistics for each stage
    $queueLatency = Get-LatencyStats -Values ($fetched.latency_ms | ForEach-Object { [double]$_ })
    $processLatency = Get-LatencyStats -Values ($processed.latency_ms | ForEach-Object { [double]$_ })
    $e2eLatency = Get-LatencyStats -Values ($completed.latency_ms | ForEach-Object { [double]$_ })
    
    return @{
        Environment = $Env
        File = (Split-Path $FilePath -Leaf)
        QueueLatency = $queueLatency
        ProcessLatency = $processLatency
        EndToEndLatency = $e2eLatency
        TotalOrders = $completed.Count
        QueueDepthAvg = [math]::Round(($data.queue_depth | Measure-Object -Average).Average, 2)
        QueueDepthMax = ($data.queue_depth | Measure-Object -Maximum).Maximum
    }
}

function Format-StatsTable {
    param($Stats, $Label)
    
    Write-Host "`n  $Label" -ForegroundColor Yellow
    Write-Host "  $("-" * 70)"
    Write-Host ("    {0,-15} {1,10} {2,10} {3,10} {4,10} {5,10}" -f "Metric", "Mean", "Median", "P95", "P99", "Max")
    Write-Host ("    {0,-15} {1,10:F2} {2,10:F2} {3,10:F2} {4,10:F2} {5,10:F2}" -f `
        "", $Stats.Mean, $Stats.Median, $Stats.P95, $Stats.P99, $Stats.Max)
    Write-Host ("    {0,-15} {1,10:F2}" -f "Std Dev", $Stats.StdDev)
    Write-Host ("    {0,-15} {1,10}" -f "Sample Count", $Stats.Count)
}

# Main execution
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "LATENCY STAGES ANALYSIS" -ForegroundColor Cyan
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""
Write-Host "This analysis breaks down latency into three stages:" -ForegroundColor White
Write-Host "  1. Queue Latency: Time from order creation to fetch from queue (SNS->SQS->Processor fetch)"
Write-Host "  2. Processing Latency: Time spent in payment simulation (default 3 seconds)"
Write-Host "  3. End-to-End Latency: Total time from creation to completion"
Write-Host ""

# Find metrics files
$environments = @()
if ($Environment -eq "both") {
    $environments = @("localstack", "aws")
} else {
    $environments = @($Environment)
}

$allResults = @()

foreach ($env in $environments) {
    Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
    Write-Host "ANALYZING: $($env.ToUpper())" -ForegroundColor Cyan
    Write-Host "$("=" * 80)" -ForegroundColor Cyan
    
    $metricsFiles = Get-ChildItem -Path $MetricsPath -Filter "metrics_${env}_*.csv" -ErrorAction SilentlyContinue
    
    if ($metricsFiles.Count -eq 0) {
        Write-Host "No metrics files found for $env in $MetricsPath" -ForegroundColor Yellow
        Write-Host "Looking for pattern: metrics_${env}_*.csv" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Found $($metricsFiles.Count) metrics file(s)" -ForegroundColor Green
    
    foreach ($file in $metricsFiles) {
        $result = Analyze-MetricsFile -FilePath $file.FullName -Env $env
        
        if ($result) {
            $allResults += $result
            
            Write-Host "`n$("-" * 80)" -ForegroundColor White
            Write-Host "LATENCY BREAKDOWN" -ForegroundColor White
            Write-Host "$("-" * 80)" -ForegroundColor White
            
            Format-StatsTable -Stats $result.QueueLatency -Label "1. QUEUE LATENCY (Creation -> Fetch)"
            Format-StatsTable -Stats $result.ProcessLatency -Label "2. PROCESSING LATENCY (Payment Simulation)"
            Format-StatsTable -Stats $result.EndToEndLatency -Label "3. END-TO-END LATENCY (Creation -> Completion)"
            
            Write-Host "`n  Queue Depth Statistics" -ForegroundColor Yellow
            Write-Host "  $("-" * 70)"
            Write-Host ("    {0,-20} {1,10}" -f "Average Depth", $result.QueueDepthAvg)
            Write-Host ("    {0,-20} {1,10}" -f "Max Depth", $result.QueueDepthMax)
            
            Write-Host "`n  Performance Summary" -ForegroundColor Yellow
            Write-Host "  $("-" * 70)"
            $queuePct = [math]::Round(($result.QueueLatency.Mean / $result.EndToEndLatency.Mean) * 100, 1)
            $processPct = [math]::Round(($result.ProcessLatency.Mean / $result.EndToEndLatency.Mean) * 100, 1)
            Write-Host ("    Queue Latency: {0:F2}ms ({1}% of total)" -f $result.QueueLatency.Mean, $queuePct)
            Write-Host ("    Processing Latency: {0:F2}ms ({1}% of total)" -f $result.ProcessLatency.Mean, $processPct)
            Write-Host ("    End-to-End Latency: {0:F2}ms (100%)" -f $result.EndToEndLatency.Mean)
        }
    }
}

# Comparison if both environments analyzed
if ($allResults.Count -ge 2) {
    Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
    Write-Host "ENVIRONMENT COMPARISON" -ForegroundColor Cyan
    Write-Host "$("=" * 80)" -ForegroundColor Cyan
    
    $localstackResults = $allResults | Where-Object { $_.Environment -eq "localstack" } | Select-Object -Last 1
    $awsResults = $allResults | Where-Object { $_.Environment -eq "aws" } | Select-Object -Last 1
    
    if ($localstackResults -and $awsResults) {
        Write-Host "`n  Queue Latency Comparison" -ForegroundColor Yellow
        Write-Host "  $("-" * 70)"
        Write-Host ("    {0,-20} {1,12} {2,12} {3,15}" -f "Environment", "Mean (ms)", "P95 (ms)", "Speedup")
        Write-Host ("    {0,-20} {1,12:F2} {2,12:F2} {3,15}" -f "LocalStack", `
            $localstackResults.QueueLatency.Mean, $localstackResults.QueueLatency.P95, "Baseline")
        Write-Host ("    {0,-20} {1,12:F2} {2,12:F2} {3,15:F2}x" -f "AWS", `
            $awsResults.QueueLatency.Mean, $awsResults.QueueLatency.P95, `
            ($awsResults.QueueLatency.Mean / $localstackResults.QueueLatency.Mean))
        
        Write-Host "`n  End-to-End Latency Comparison" -ForegroundColor Yellow
        Write-Host "  $("-" * 70)"
        Write-Host ("    {0,-20} {1,12} {2,12} {3,15}" -f "Environment", "Mean (ms)", "P95 (ms)", "Speedup")
        Write-Host ("    {0,-20} {1,12:F2} {2,12:F2} {3,15}" -f "LocalStack", `
            $localstackResults.EndToEndLatency.Mean, $localstackResults.EndToEndLatency.P95, "Baseline")
        Write-Host ("    {0,-20} {1,12:F2} {2,12:F2} {3,15:F2}x" -f "AWS", `
            $awsResults.EndToEndLatency.Mean, $awsResults.EndToEndLatency.P95, `
            ($awsResults.EndToEndLatency.Mean / $localstackResults.EndToEndLatency.Mean))
        
        Write-Host "`n  Key Insights" -ForegroundColor Yellow
        Write-Host "  $("-" * 70)"
        $queueSpeedup = $awsResults.QueueLatency.Mean / $localstackResults.QueueLatency.Mean
        $e2eSpeedup = $awsResults.EndToEndLatency.Mean / $localstackResults.EndToEndLatency.Mean
        
        if ($queueSpeedup -gt 1.5) {
            Write-Host "    • AWS queue latency is $("{0:F1}x" -f $queueSpeedup) slower than LocalStack" -ForegroundColor Red
            Write-Host "      This indicates network/region overhead in AWS" -ForegroundColor Gray
        } elseif ($queueSpeedup -lt 0.7) {
            Write-Host "    • LocalStack queue latency is $("{0:F1}x" -f (1/$queueSpeedup)) slower than AWS" -ForegroundColor Red
        } else {
            Write-Host "    • Queue latency is similar between environments" -ForegroundColor Green
        }
        
        Write-Host ("    • Processing latency is consistent (simulated {0:F0}s delay)" -f ($localstackResults.ProcessLatency.Mean / 1000)) -ForegroundColor Green
        Write-Host ("    • Total throughput: LocalStack={0}, AWS={1}" -f $localstackResults.TotalOrders, $awsResults.TotalOrders) -ForegroundColor White
    }
}

Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
Write-Host ""

# Export to CSV if requested
if ($OutputFormat -eq "csv" -and $allResults.Count -gt 0) {
    $outputFile = "latency_stages_analysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $csvData = @()
    
    foreach ($result in $allResults) {
        $csvData += [PSCustomObject]@{
            Environment = $result.Environment
            File = $result.File
            TotalOrders = $result.TotalOrders
            QueueLatency_Mean = $result.QueueLatency.Mean
            QueueLatency_P95 = $result.QueueLatency.P95
            QueueLatency_P99 = $result.QueueLatency.P99
            ProcessLatency_Mean = $result.ProcessLatency.Mean
            ProcessLatency_P95 = $result.ProcessLatency.P95
            EndToEndLatency_Mean = $result.EndToEndLatency.Mean
            EndToEndLatency_P95 = $result.EndToEndLatency.P95
            EndToEndLatency_P99 = $result.EndToEndLatency.P99
            QueueDepth_Avg = $result.QueueDepthAvg
            QueueDepth_Max = $result.QueueDepthMax
        }
    }
    
    $csvData | Export-Csv -Path $outputFile -NoTypeInformation
    Write-Host "Results exported to: $outputFile" -ForegroundColor Green
}
