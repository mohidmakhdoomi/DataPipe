# PowerShell script to stop local Airflow development environment

Write-Host "Stopping Development Environment" -ForegroundColor Red
Write-Host "=========================================" -ForegroundColor Red

try {
    # Stop and remove containers
    Write-Host "Stopping Docker Compose services..." -ForegroundColor Yellow
    docker-compose -f docker/docker-compose.yml down -v
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker services stopped successfully!" -ForegroundColor Green
        
        # Optional: Remove volumes (uncomment if you want to clean up data)
        # Write-Host "Removing volumes..." -ForegroundColor Yellow
        # docker-compose -f docker/docker-compose.yml down -v
        
        Write-Host ""
        Write-Host "Services stopped" -ForegroundColor Cyan
        
    } else {
        Write-Host "Failed to stop some services" -ForegroundColor Red
        Write-Host "You may need to stop them manually" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Error stopping services: $_" -ForegroundColor Red
}