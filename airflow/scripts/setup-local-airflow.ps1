# PowerShell script to set up local Airflow without Docker

Write-Host "Setting up Local Airflow Environment" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# Check if Python is available
try {
    $pythonVersion = python --version 2>&1
    Write-Host "Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "Python is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Python 3.8+ from https://python.org" -ForegroundColor Yellow
    exit 1
}

# Create virtual environment
if (-not (Test-Path "venv")) {
    Write-Host "Creating Python virtual environment..." -ForegroundColor Yellow
    python -m venv venv
    Write-Host "Virtual environment created" -ForegroundColor Green
}

# Activate virtual environment
Write-Host "Activating virtual environment..." -ForegroundColor Yellow
& ".\venv\Scripts\Activate.ps1"

# Install requirements
Write-Host "Installing Airflow and dependencies..." -ForegroundColor Yellow
Write-Host "This may take several minutes..." -ForegroundColor Gray

# Set Airflow home
$env:AIRFLOW_HOME = (Get-Location).Path

# Install Airflow with constraints
$AIRFLOW_VERSION = "2.8.0"
$PYTHON_VERSION = "3.11"
$CONSTRAINT_URL = "https://raw.githubusercontent.com/apache/airflow/constraints-$AIRFLOW_VERSION/constraints-$PYTHON_VERSION.txt"

pip install "apache-airflow==$AIRFLOW_VERSION" --constraint $CONSTRAINT_URL

# Install additional packages
pip install -r requirements.txt

# Initialize Airflow database
Write-Host "Initializing Airflow database..." -ForegroundColor Yellow
airflow db init

# Create admin user
Write-Host "Creating admin user..." -ForegroundColor Yellow
airflow users create `
    --username admin `
    --firstname Admin `
    --lastname User `
    --role Admin `
    --email admin@example.com `
    --password admin

Write-Host "Setup completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To start Airflow:" -ForegroundColor Cyan
Write-Host "1. Activate virtual environment: .\venv\Scripts\Activate.ps1" -ForegroundColor White
Write-Host "2. Start webserver: airflow webserver --port 8080" -ForegroundColor White
Write-Host "3. Start scheduler (in new terminal): airflow scheduler" -ForegroundColor White
Write-Host ""
Write-Host "Then access Airflow at: http://localhost:8080" -ForegroundColor White
Write-Host "Username: admin, Password: admin" -ForegroundColor White