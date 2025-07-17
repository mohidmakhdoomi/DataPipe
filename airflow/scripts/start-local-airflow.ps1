# PowerShell script to start local Airflow services

Write-Host "Starting Local Airflow Services" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Check if virtual environment exists
if (-not (Test-Path "venv")) {
    Write-Host "Virtual environment not found. Please run setup-local-airflow.ps1 first." -ForegroundColor Red
    exit 1
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& ".\venv\Scripts\Activate.ps1"

# Set Airflow home
$env:AIRFLOW_HOME = (Get-Location).Path

# Check if Airflow is installed
try {
    airflow version | Out-Null
    Write-Host "Airflow is installed" -ForegroundColor Green
} catch {
    Write-Host "Airflow is not installed. Please run setup-local-airflow.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Starting Airflow services..." -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop all services" -ForegroundColor Gray
Write-Host ""

# Start webserver and scheduler in background
Write-Host "Starting Airflow webserver on port 8080..." -ForegroundColor Green
Start-Process -FilePath "airflow" -ArgumentList "webserver", "--port", "8080" -WindowStyle Minimized

Write-Host "Starting Airflow scheduler..." -ForegroundColor Green
Start-Process -FilePath "airflow" -ArgumentList "scheduler" -WindowStyle Minimized

Write-Host ""
Write-Host "Services started!" -ForegroundColor Green
Write-Host "Access Airflow at: http://localhost:8080" -ForegroundColor Cyan
Write-Host "Username: admin, Password: admin" -ForegroundColor White
Write-Host ""
Write-Host "To stop services, close the Airflow windows or run:" -ForegroundColor Yellow
Write-Host "Get-Process airflow | Stop-Process" -ForegroundColor White

# Wait for user input to keep script running
Write-Host ""
Write-Host "Press any key to exit this script (services will continue running)..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")