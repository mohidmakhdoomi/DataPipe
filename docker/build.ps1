# PowerShell script to build all Docker containers

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "base", "data-generator", "airflow", "dbt", "clickhouse", "kafka-tools")]
    [string]$Service = "all",
    
    [Parameter(Mandatory=$false)]
    [switch]$NoBuildCache,
    
    [Parameter(Mandatory=$false)]
    [switch]$Parallel
)

Write-Host "🐳 Building Docker containers for Data Pipeline" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

$services = @()

if ($Service -eq "all") {
    $services = @("base", "data-generator", "airflow", "dbt", "clickhouse", "kafka-tools")
} else {
    $services = @($Service)
}

$buildArgs = @()
if ($NoBuildCache) {
    $buildArgs += "--no-cache"
}

function Build-Service {
    param($ServiceName)
    
    Write-Host "🔨 Building $ServiceName..." -ForegroundColor Green
    
    $buildCommand = @("docker", "build") + $buildArgs + @("-t", "data-pipeline/$ServiceName", "$ServiceName/")
    
    try {
        & $buildCommand[0] $buildCommand[1..($buildCommand.Length-1)]
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $ServiceName built successfully!" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to build $ServiceName" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error building $ServiceName`: $_" -ForegroundColor Red
        return $false
    }
    
    return $true
}

$startTime = Get-Date

if ($Parallel -and $services.Count -gt 1) {
    Write-Host "🚀 Building services in parallel..." -ForegroundColor Yellow
    
    $jobs = @()
    foreach ($service in $services) {
        if ($service -ne "base") {  # Base must be built first
            $jobs += Start-Job -ScriptBlock ${function:Build-Service} -ArgumentList $service
        }
    }
    
    # Build base first if it's in the list
    if ($services -contains "base") {
        Build-Service "base"
    }
    
    # Wait for parallel jobs
    $jobs | Wait-Job | Receive-Job
    $jobs | Remove-Job
    
} else {
    Write-Host "🔄 Building services sequentially..." -ForegroundColor Yellow
    
    $successCount = 0
    foreach ($service in $services) {
        if (Build-Service $service) {
            $successCount++
        }
    }
    
    Write-Host "📊 Build Summary:" -ForegroundColor Cyan
    Write-Host "  ✅ Successful: $successCount" -ForegroundColor Green
    Write-Host "  ❌ Failed: $($services.Count - $successCount)" -ForegroundColor Red
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "⏱️  Total build time: $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host "🎉 Build process completed!" -ForegroundColor Green

# Show built images
Write-Host "`n📋 Built images:" -ForegroundColor Cyan
docker images | Select-String "data-pipeline"