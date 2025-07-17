# PowerShell script to deploy Kubernetes manifests

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "infrastructure", "databases", "pipeline", "monitoring", "cleanup")]
    [string]$Component = "all",
    
    [Parameter(Mandatory=$false)]
    [string]$Namespace = "",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Wait
)

Write-Host "🚀 Deploying Data Pipeline to Kubernetes" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Check if kubectl is available
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "❌ kubectl is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install kubectl and configure access to your EKS cluster" -ForegroundColor Yellow
    exit 1
}

# Check cluster connection
try {
    $clusterInfo = kubectl cluster-info --request-timeout=5s 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Cannot connect to Kubernetes cluster" -ForegroundColor Red
        Write-Host "Please ensure kubectl is configured for your EKS cluster:" -ForegroundColor Yellow
        Write-Host "  aws eks update-kubeconfig --region us-west-2 --name data-pipeline-dev-cluster" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "✅ Connected to Kubernetes cluster" -ForegroundColor Green
} catch {
    Write-Host "❌ Error connecting to cluster: $_" -ForegroundColor Red
    exit 1
}

function Deploy-Manifests {
    param($Path, $Description)
    
    if (-not (Test-Path $Path)) {
        Write-Host "⚠️  Path $Path not found, skipping..." -ForegroundColor Yellow
        return
    }
    
    Write-Host "📦 Deploying $Description..." -ForegroundColor Green
    
    $kubectlArgs = @("apply", "-f", $Path)
    if ($DryRun) {
        $kubectlArgs += "--dry-run=client"
    }
    if ($Namespace) {
        $kubectlArgs += "-n", $Namespace
    }
    
    try {
        & kubectl $kubectlArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $Description deployed successfully" -ForegroundColor Green
        } else {
            Write-Host "❌ Failed to deploy $Description" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "❌ Error deploying $Description`: $_" -ForegroundColor Red
        return $false
    }
    
    return $true
}

function Wait-ForDeployment {
    param($DeploymentName, $Namespace)
    
    Write-Host "⏳ Waiting for $DeploymentName to be ready..." -ForegroundColor Yellow
    
    try {
        kubectl wait --for=condition=available --timeout=300s deployment/$DeploymentName -n $Namespace
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ $DeploymentName is ready" -ForegroundColor Green
        } else {
            Write-Host "⚠️  $DeploymentName may not be fully ready" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "⚠️  Could not wait for $DeploymentName`: $_" -ForegroundColor Yellow
    }
}

$startTime = Get-Date

switch ($Component) {
    "infrastructure" {
        Deploy-Manifests "namespaces/" "Namespaces"
        Deploy-Manifests "storage/" "Storage Classes and PVCs"
        Deploy-Manifests "secrets/" "Secrets"
        Deploy-Manifests "configmaps/" "ConfigMaps"
    }
    
    "databases" {
        Deploy-Manifests "databases/postgres.yaml" "PostgreSQL"
        Deploy-Manifests "databases/clickhouse.yaml" "ClickHouse"
        Deploy-Manifests "databases/kafka.yaml" "Kafka Cluster"
        
        if ($Wait) {
            Wait-ForDeployment "postgres" "data-storage"
            Wait-ForDeployment "clickhouse" "data-storage"
            Wait-ForDeployment "kafka" "data-storage"
        }
    }
    
    "pipeline" {
        Deploy-Manifests "airflow/" "Airflow Components"
        Deploy-Manifests "dbt/" "dbt Jobs"
        Deploy-Manifests "data-generator/" "Data Generator and Kafka Tools"
        
        if ($Wait) {
            Wait-ForDeployment "airflow-scheduler" "data-pipeline"
            Wait-ForDeployment "airflow-webserver" "data-pipeline"
            Wait-ForDeployment "data-generator" "data-pipeline"
            Wait-ForDeployment "kafka-tools" "data-pipeline"
        }
    }
    
    "monitoring" {
        if (Test-Path "monitoring/") {
            Deploy-Manifests "monitoring/" "Monitoring Stack"
        } else {
            Write-Host "⚠️  Monitoring manifests not found, skipping..." -ForegroundColor Yellow
        }
    }
    
    "cleanup" {
        Write-Host "🧹 Cleaning up resources..." -ForegroundColor Red
        Write-Host "⚠️  This will delete all data pipeline resources!" -ForegroundColor Yellow
        
        $confirm = Read-Host "Are you sure you want to delete all resources? (yes/no)"
        if ($confirm -eq "yes") {
            kubectl delete namespace data-pipeline --ignore-not-found=true
            kubectl delete namespace data-storage --ignore-not-found=true
            kubectl delete namespace data-pipeline-system --ignore-not-found=true
            Write-Host "✅ Cleanup completed" -ForegroundColor Green
        } else {
            Write-Host "❌ Cleanup cancelled" -ForegroundColor Yellow
        }
        return
    }
    
    "all" {
        # Deploy in order
        Deploy-Manifests "namespaces/" "Namespaces"
        Start-Sleep -Seconds 5
        
        Deploy-Manifests "storage/" "Storage Classes and PVCs"
        Deploy-Manifests "secrets/" "Secrets"
        Deploy-Manifests "configmaps/" "ConfigMaps"
        Start-Sleep -Seconds 10
        
        Deploy-Manifests "databases/postgres.yaml" "PostgreSQL"
        Deploy-Manifests "databases/clickhouse.yaml" "ClickHouse"
        Deploy-Manifests "databases/kafka.yaml" "Kafka Cluster"
        
        if ($Wait) {
            Write-Host "⏳ Waiting for databases to be ready..." -ForegroundColor Yellow
            Start-Sleep -Seconds 30
        }
        
        Deploy-Manifests "airflow/" "Airflow Components"
        Deploy-Manifests "dbt/" "dbt Jobs"
        Deploy-Manifests "data-generator/" "Data Generator and Kafka Tools"
        
        if (Test-Path "monitoring/") {
            Deploy-Manifests "monitoring/" "Monitoring Stack"
        }
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "⏱️  Deployment completed in $($duration.ToString('mm\:ss'))" -ForegroundColor Cyan

# Show deployment status
Write-Host "`n📊 Deployment Status:" -ForegroundColor Cyan
Write-Host "Namespaces:" -ForegroundColor Yellow
kubectl get namespaces | Select-String "data-"

Write-Host "`nPods in data-pipeline namespace:" -ForegroundColor Yellow
kubectl get pods -n data-pipeline 2>$null

Write-Host "`nPods in data-storage namespace:" -ForegroundColor Yellow
kubectl get pods -n data-storage 2>$null

Write-Host "`nServices:" -ForegroundColor Yellow
kubectl get services -n data-pipeline 2>$null
kubectl get services -n data-storage 2>$null

Write-Host "`n🎉 Deployment process completed!" -ForegroundColor Green
Write-Host "`n📋 Next steps:" -ForegroundColor Cyan
Write-Host "  1. Check pod status: kubectl get pods -n data-pipeline" -ForegroundColor White
Write-Host "  2. Access Airflow UI: kubectl port-forward svc/airflow-webserver 8080:8080 -n data-pipeline" -ForegroundColor White
Write-Host "  3. Access ClickHouse: kubectl port-forward svc/clickhouse 8123:8123 -n data-storage" -ForegroundColor White
Write-Host "  4. View logs: kubectl logs -f deployment/airflow-scheduler -n data-pipeline" -ForegroundColor White