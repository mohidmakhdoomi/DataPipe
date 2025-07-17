# PowerShell script to check the status of the data pipeline

Write-Host "📊 Data Pipeline Status Check" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

# Check if kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "❌ kubectl is not installed or not in PATH" -ForegroundColor Red
    exit 1
}

# Check cluster connection
try {
    kubectl cluster-info --request-timeout=5s | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Cannot connect to Kubernetes cluster" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Connected to Kubernetes cluster" -ForegroundColor Green
} catch {
    Write-Host "❌ Error connecting to cluster" -ForegroundColor Red
    exit 1
}

Write-Host "`n🏷️  Namespaces:" -ForegroundColor Yellow
kubectl get namespaces | Select-String "data-"

Write-Host "`n💾 Storage:" -ForegroundColor Yellow
Write-Host "Persistent Volume Claims:" -ForegroundColor Gray
kubectl get pvc -n data-storage 2>$null
kubectl get pvc -n data-pipeline 2>$null

Write-Host "`n🗄️  Database Services:" -ForegroundColor Yellow
Write-Host "PostgreSQL:" -ForegroundColor Gray
kubectl get pods -n data-storage -l app=postgres -o wide 2>$null

Write-Host "ClickHouse:" -ForegroundColor Gray
kubectl get pods -n data-storage -l app=clickhouse -o wide 2>$null

Write-Host "Kafka:" -ForegroundColor Gray
kubectl get pods -n data-storage -l app=kafka -o wide 2>$null

Write-Host "`n🔄 Pipeline Services:" -ForegroundColor Yellow
Write-Host "Airflow:" -ForegroundColor Gray
kubectl get pods -n data-pipeline -l app=airflow -o wide 2>$null

Write-Host "Data Generator:" -ForegroundColor Gray
kubectl get pods -n data-pipeline -l app=data-generator -o wide 2>$null

Write-Host "Kafka Tools:" -ForegroundColor Gray
kubectl get pods -n data-pipeline -l app=kafka-tools -o wide 2>$null

Write-Host "`n🌐 Services:" -ForegroundColor Yellow
Write-Host "Data Storage Services:" -ForegroundColor Gray
kubectl get services -n data-storage 2>$null

Write-Host "Pipeline Services:" -ForegroundColor Gray
kubectl get services -n data-pipeline 2>$null

Write-Host "`n📋 Jobs and CronJobs:" -ForegroundColor Yellow
kubectl get jobs,cronjobs -n data-pipeline 2>$null

Write-Host "`n🔍 Resource Usage:" -ForegroundColor Yellow
Write-Host "Node Resource Usage:" -ForegroundColor Gray
kubectl top nodes 2>$null

Write-Host "Pod Resource Usage (data-pipeline):" -ForegroundColor Gray
kubectl top pods -n data-pipeline 2>$null

Write-Host "Pod Resource Usage (data-storage):" -ForegroundColor Gray
kubectl top pods -n data-storage 2>$null

Write-Host "`n🚨 Recent Events:" -ForegroundColor Yellow
kubectl get events --sort-by=.metadata.creationTimestamp -n data-pipeline --tail=5 2>$null
kubectl get events --sort-by=.metadata.creationTimestamp -n data-storage --tail=5 2>$null

Write-Host "`n✅ Status check completed!" -ForegroundColor Green
Write-Host "`n📋 Quick Access Commands:" -ForegroundColor Cyan
Write-Host "  Airflow UI:    .\scripts\port-forward.ps1 -Service airflow" -ForegroundColor White
Write-Host "  ClickHouse:    .\scripts\port-forward.ps1 -Service clickhouse" -ForegroundColor White
Write-Host "  View logs:     .\scripts\logs.ps1 -Service airflow-scheduler -Follow" -ForegroundColor White