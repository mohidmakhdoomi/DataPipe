# PowerShell script for easy port forwarding to services

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("airflow", "clickhouse", "postgres", "kafka", "grafana")]
    [string]$Service,
    
    [Parameter(Mandatory=$false)]
    [int]$LocalPort = 0
)

Write-Host "🔗 Setting up port forwarding for $Service" -ForegroundColor Cyan

switch ($Service) {
    "airflow" {
        $port = if ($LocalPort -eq 0) { 8080 } else { $LocalPort }
        Write-Host "🌐 Airflow UI will be available at: http://localhost:$port" -ForegroundColor Green
        Write-Host "📝 Default credentials: admin / admin" -ForegroundColor Yellow
        kubectl port-forward svc/airflow-webserver $port`:8080 -n data-pipeline
    }
    
    "clickhouse" {
        $port = if ($LocalPort -eq 0) { 8123 } else { $LocalPort }
        Write-Host "🗄️  ClickHouse will be available at: http://localhost:$port" -ForegroundColor Green
        Write-Host "📝 Default credentials: analytics_user / analytics_password" -ForegroundColor Yellow
        kubectl port-forward svc/clickhouse $port`:8123 -n data-storage
    }
    
    "postgres" {
        $port = if ($LocalPort -eq 0) { 5432 } else { $LocalPort }
        Write-Host "🐘 PostgreSQL will be available at: localhost:$port" -ForegroundColor Green
        Write-Host "📝 Default credentials: postgres / postgres_password" -ForegroundColor Yellow
        kubectl port-forward svc/postgres $port`:5432 -n data-storage
    }
    
    "kafka" {
        $port = if ($LocalPort -eq 0) { 9092 } else { $LocalPort }
        Write-Host "📨 Kafka will be available at: localhost:$port" -ForegroundColor Green
        kubectl port-forward svc/kafka $port`:9092 -n data-storage
    }
    
    "grafana" {
        $port = if ($LocalPort -eq 0) { 3000 } else { $LocalPort }
        Write-Host "📊 Grafana will be available at: http://localhost:$port" -ForegroundColor Green
        Write-Host "📝 Default credentials: admin / admin" -ForegroundColor Yellow
        kubectl port-forward svc/grafana $port`:3000 -n data-pipeline-system
    }
}

Write-Host "Press Ctrl+C to stop port forwarding" -ForegroundColor Yellow