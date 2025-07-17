# PowerShell script to test DAG syntax and functionality

param(
    [Parameter(Mandatory=$false)]
    [string]$DagId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$TaskId = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ExecutionDate = (Get-Date -Format "yyyy-MM-dd")
)

Write-Host "🧪 Testing Airflow DAGs" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor Cyan

# Check if Airflow is running
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -UseBasicParsing
    if ($response.StatusCode -ne 200) {
        Write-Host "❌ Airflow is not running. Start it with: .\scripts\start-airflow.ps1" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Airflow is running" -ForegroundColor Green
} catch {
    Write-Host "❌ Airflow is not accessible. Start it with: .\scripts\start-airflow.ps1" -ForegroundColor Red
    exit 1
}

# Test DAG syntax
Write-Host "📝 Testing DAG syntax..." -ForegroundColor Yellow

$dagFiles = Get-ChildItem -Path "dags" -Filter "*.py" | Where-Object { $_.Name -ne "__init__.py" }

foreach ($dagFile in $dagFiles) {
    Write-Host "  Testing $($dagFile.Name)..." -ForegroundColor Gray
    
    try {
        # Test Python syntax
        python -m py_compile "dags/$($dagFile.Name)"
        Write-Host "    ✅ Syntax OK" -ForegroundColor Green
        
        # Test DAG loading (if specific DAG not specified)
        if (-not $DagId -or $dagFile.BaseName -eq $DagId) {
            $testResult = docker-compose exec -T airflow-scheduler airflow dags list-import-errors 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "    ✅ DAG loads successfully" -ForegroundColor Green
            } else {
                Write-Host "    ⚠️  DAG may have import issues" -ForegroundColor Yellow
            }
        }
        
    } catch {
        Write-Host "    ❌ Syntax error: $_" -ForegroundColor Red
    }
}

# If specific DAG and task specified, test the task
if ($DagId -and $TaskId) {
    Write-Host ""
    Write-Host "🎯 Testing specific task: $DagId.$TaskId" -ForegroundColor Cyan
    
    try {
        $testCommand = "airflow tasks test $DagId $TaskId $ExecutionDate"
        Write-Host "Running: $testCommand" -ForegroundColor Gray
        
        docker-compose exec airflow-scheduler $testCommand
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Task test completed successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Task test failed" -ForegroundColor Red
        }
        
    } catch {
        Write-Host "❌ Error testing task: $_" -ForegroundColor Red
    }
}

# List all DAGs
Write-Host ""
Write-Host "📋 Available DAGs:" -ForegroundColor Cyan

try {
    docker-compose exec -T airflow-scheduler airflow dags list
} catch {
    Write-Host "❌ Could not list DAGs" -ForegroundColor Red
}

Write-Host ""
Write-Host "💡 Usage examples:" -ForegroundColor Cyan
Write-Host "  Test specific DAG:  .\test-dags.ps1 -DagId 'data_pipeline_main'" -ForegroundColor White
Write-Host "  Test specific task: .\test-dags.ps1 -DagId 'data_pipeline_main' -TaskId 'extract_data'" -ForegroundColor White
Write-Host "  Custom date:        .\test-dags.ps1 -DagId 'data_pipeline_main' -TaskId 'extract_data' -ExecutionDate '2024-01-01'" -ForegroundColor White