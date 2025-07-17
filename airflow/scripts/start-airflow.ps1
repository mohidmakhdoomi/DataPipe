# PowerShell script to start local Airflow development environment

Write-Host "Starting Airflow Development Environment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Check if Docker is running
try {
    docker info | Out-Null
    Write-Host "Docker is running" -ForegroundColor Green
} catch {
    Write-Host "Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-Host "Creating .env file from template..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
    Write-Host "Created .env file. You can customize it if needed." -ForegroundColor Green
}

# Create required directories
$directories = @("dags", "logs", "plugins", "config")
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created directory: $dir" -ForegroundColor Green
    }
}

# Set AIRFLOW_UID for Linux compatibility
$env:AIRFLOW_UID = "50000"

Write-Host "Starting Docker Compose services..." -ForegroundColor Yellow
Write-Host "This may take a few minutes on first run..." -ForegroundColor Gray

try {
    # Start services
    docker-compose up -d
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Airflow services started successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Access points:" -ForegroundColor Cyan
        Write-Host "  Airflow UI:    http://localhost:8080" -ForegroundColor White
        Write-Host "  Username:      admin" -ForegroundColor White
        Write-Host "  Password:      admin" -ForegroundColor White
        Write-Host ""
        Write-Host "  PostgreSQL:    localhost:5433" -ForegroundColor White
        Write-Host "  ClickHouse:    http://localhost:8123" -ForegroundColor White
        Write-Host ""
        Write-Host "Useful commands:" -ForegroundColor Cyan
        Write-Host "  View logs:     docker-compose logs -f" -ForegroundColor White
        Write-Host "  Stop services: docker-compose down" -ForegroundColor White
        Write-Host "  Restart:       docker-compose restart" -ForegroundColor White
        Write-Host ""
        Write-Host "Waiting for services to be ready..." -ForegroundColor Yellow
        
        # Wait for Airflow to be ready
        $maxAttempts = 30
        $attempt = 0
        do {
            Start-Sleep -Seconds 10
            $attempt++
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 5 -UseBasicParsing
                if ($response.StatusCode -eq 200) {
                    Write-Host "Airflow is ready!" -ForegroundColor Green
                    Write-Host "You can now access Airflow at http://localhost:8080" -ForegroundColor Green
                    break
                }
            } catch {
                Write-Host "Attempt $attempt/$maxAttempts - Airflow not ready yet..." -ForegroundColor Gray
            }
        } while ($attempt -lt $maxAttempts)
        
        if ($attempt -eq $maxAttempts) {
            Write-Host "Airflow may still be starting up. Check logs with: docker-compose logs -f" -ForegroundColor Yellow
        }
        
    } else {
        Write-Host "Failed to start Airflow services" -ForegroundColor Red
        Write-Host "Check logs with: docker-compose logs" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Error starting services: $_" -ForegroundColor Red
}