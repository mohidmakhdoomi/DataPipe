# Airflow and Data Pipeline Testing Script
# This script tests the complete Docker Compose setup

Write-Host "🚀 Starting Airflow and Data Pipeline Tests..." -ForegroundColor Green

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-Host "❌ .env file not found. Please copy .env.example to .env and configure it." -ForegroundColor Red
    Write-Host "Run: cp .env.example .env" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ .env file found" -ForegroundColor Green

# Function to check if service is healthy
function Test-ServiceHealth {
    param(
        [string]$ServiceName,
        [string]$HealthCommand,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 10
    )
    
    Write-Host "🔍 Testing $ServiceName health..." -ForegroundColor Cyan
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            $result = Invoke-Expression $HealthCommand
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ $ServiceName is healthy" -ForegroundColor Green
                return $true
            }
        }
        catch {
            # Continue trying
        }
        
        Write-Host "⏳ Waiting for $ServiceName... (attempt $i/$MaxRetries)" -ForegroundColor Yellow
        Start-Sleep -Seconds $DelaySeconds
    }
    
    Write-Host "❌ $ServiceName failed to become healthy" -ForegroundColor Red
    return $false
}

# Start services
Write-Host "`n📦 Starting Docker Compose services..." -ForegroundColor Cyan
docker-compose up -d

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Failed to start Docker Compose services" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Docker Compose services started" -ForegroundColor Green

# Wait for services to be ready
Write-Host "`n🔍 Checking service health..." -ForegroundColor Cyan

# Test PostgreSQL
$postgresHealthy = Test-ServiceHealth -ServiceName "PostgreSQL" -HealthCommand "docker-compose exec -T postgres pg_isready -U postgres"

# Test Kafka
$kafkaHealthy = Test-ServiceHealth -ServiceName "Kafka" -HealthCommand "docker-compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --list"

# Test ClickHouse
$clickhouseHealthy = Test-ServiceHealth -ServiceName "ClickHouse" -HealthCommand "docker-compose exec -T clickhouse clickhouse-client --query 'SELECT 1'"

# Test Airflow Webserver
$airflowHealthy = Test-ServiceHealth -ServiceName "Airflow Webserver" -HealthCommand "curl -f http://localhost:8080/health" -MaxRetries 60

# Run Airflow tests
if ($airflowHealthy) {
    Write-Host "`n🧪 Running Airflow configuration tests..." -ForegroundColor Cyan
    docker-compose exec -T airflow-scheduler python /opt/airflow/scripts/test_airflow_setup.py
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Airflow configuration tests passed" -ForegroundColor Green
    } else {
        Write-Host "❌ Airflow configuration tests failed" -ForegroundColor Red
    }
}

# Test DAG parsing
Write-Host "`n🔍 Testing DAG parsing..." -ForegroundColor Cyan
docker-compose exec -T airflow-scheduler airflow dags list

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ DAG parsing successful" -ForegroundColor Green
} else {
    Write-Host "❌ DAG parsing failed" -ForegroundColor Red
}

# Test database connections
Write-Host "`n🔍 Testing database connections..." -ForegroundColor Cyan
docker-compose exec -T airflow-scheduler airflow connections test postgres_default

# Test DAG structure
Write-Host "`n🔍 Testing DAG structure..." -ForegroundColor Cyan
docker-compose exec -T airflow-scheduler airflow dags show data_pipeline_main

# Show service status
Write-Host "`n📊 Service Status Summary:" -ForegroundColor Cyan
Write-Host "PostgreSQL: $(if ($postgresHealthy) { '✅ Healthy' } else { '❌ Unhealthy' })"
Write-Host "Kafka: $(if ($kafkaHealthy) { '✅ Healthy' } else { '❌ Unhealthy' })"
Write-Host "ClickHouse: $(if ($clickhouseHealthy) { '✅ Healthy' } else { '❌ Unhealthy' })"
Write-Host "Airflow: $(if ($airflowHealthy) { '✅ Healthy' } else { '❌ Unhealthy' })"

# Show useful URLs
Write-Host "`n🌐 Service URLs:" -ForegroundColor Cyan
Write-Host "Airflow UI: http://localhost:8080 (admin/admin)" -ForegroundColor Yellow
Write-Host "ClickHouse: http://localhost:8123" -ForegroundColor Yellow

# Final summary
$allHealthy = $postgresHealthy -and $kafkaHealthy -and $clickhouseHealthy -and $airflowHealthy

if ($allHealthy) {
    Write-Host "`n🎉 All services are healthy and ready!" -ForegroundColor Green
    Write-Host "You can now access Airflow at http://localhost:8080" -ForegroundColor Green
} else {
    Write-Host "`n⚠️ Some services are not healthy. Check the logs:" -ForegroundColor Yellow
    Write-Host "docker-compose logs [service-name]" -ForegroundColor Yellow
}

Write-Host "`n📝 Next steps:" -ForegroundColor Cyan
Write-Host "1. Access Airflow UI: http://localhost:8080" -ForegroundColor White
Write-Host "2. Enable the 'data_pipeline_main' DAG" -ForegroundColor White
Write-Host "3. Trigger a test run" -ForegroundColor White
Write-Host "4. Monitor logs: docker-compose logs -f airflow-scheduler" -ForegroundColor White