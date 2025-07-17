# PowerShell script for easy log viewing

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("airflow-scheduler", "airflow-webserver", "airflow-worker", "data-generator", "kafka-tools", "postgres", "clickhouse", "kafka")]
    [string]$Service,
    
    [Parameter(Mandatory=$false)]
    [switch]$Follow,
    
    [Parameter(Mandatory=$false)]
    [int]$Lines = 100
)

Write-Host "📋 Viewing logs for $Service" -ForegroundColor Cyan

$namespace = switch ($Service) {
    { $_ -in @("airflow-scheduler", "airflow-webserver", "airflow-worker", "data-generator", "kafka-tools") } { "data-pipeline" }
    { $_ -in @("postgres", "clickhouse", "kafka") } { "data-storage" }
    default { "data-pipeline" }
}

$kubectlArgs = @("logs")

if ($Follow) {
    $kubectlArgs += "-f"
}

$kubectlArgs += "--tail=$Lines"

# Determine if it's a deployment or statefulset
$resourceType = switch ($Service) {
    { $_ -in @("postgres", "clickhouse", "kafka") } { "statefulset" }
    default { "deployment" }
}

$kubectlArgs += "$resourceType/$Service"
$kubectlArgs += "-n", $namespace

Write-Host "🔍 Command: kubectl $($kubectlArgs -join ' ')" -ForegroundColor Gray

try {
    & kubectl $kubectlArgs
} catch {
    Write-Host "❌ Error viewing logs: $_" -ForegroundColor Red
    
    # Try to get pod logs directly
    Write-Host "🔄 Trying to get pod logs directly..." -ForegroundColor Yellow
    $pods = kubectl get pods -n $namespace -l app=$Service -o name 2>$null
    
    if ($pods) {
        $podName = ($pods | Select-Object -First 1) -replace "pod/", ""
        Write-Host "📋 Getting logs from pod: $podName" -ForegroundColor Green
        
        $podLogArgs = @("logs")
        if ($Follow) { $podLogArgs += "-f" }
        $podLogArgs += "--tail=$Lines", $podName, "-n", $namespace
        
        & kubectl $podLogArgs
    } else {
        Write-Host "❌ No pods found for service $Service in namespace $namespace" -ForegroundColor Red
    }
}