# PowerShell script to stop local Airflow development environment

Write-Host "🛑 Stopping Airflow Development Environment" -ForegroundColor Red
Write-Host "===========================================" -ForegroundColor Red

try {
    # Stop and remove containers
    Write-Host "🐳 Stopping Docker Compose services..." -ForegroundColor Yellow
    docker-compose down
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Airflow services stopped successfully!" -ForegroundColor Green
        
        # Optional: Remove volumes (uncomment if you want to clean up data)
        # Write-Host "🗑️  Removing volumes..." -ForegroundColor Yellow
        # docker-compose down -v
        
        Write-Host ""
        Write-Host "📋 Services stopped:" -ForegroundColor Cyan
        Write-Host "  - Airflow Webserver" -ForegroundColor White
        Write-Host "  - Airflow Scheduler" -ForegroundColor White
        Write-Host "  - PostgreSQL (Airflow)" -ForegroundColor White
        Write-Host "  - PostgreSQL (Data)" -ForegroundColor White
        Write-Host "  - ClickHouse" -ForegroundColor White
        Write-Host "  - Data Generator" -ForegroundColor White
        Write-Host ""
        Write-Host "💡 To completely clean up (remove data):" -ForegroundColor Cyan
        Write-Host "   docker-compose down -v" -ForegroundColor White
        
    } else {
        Write-Host "❌ Failed to stop some services" -ForegroundColor Red
        Write-Host "You may need to stop them manually:" -ForegroundColor Yellow
        Write-Host "  docker-compose down -v" -ForegroundColor White
    }
    
} catch {
    Write-Host "❌ Error stopping services: $_" -ForegroundColor Red
    Write-Host "Try running: docker-compose down -v" -ForegroundColor Yellow
}