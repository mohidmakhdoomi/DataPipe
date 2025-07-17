# PowerShell deployment script for the data pipeline infrastructure

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("init", "plan", "apply", "destroy", "output")]
    [string]$Action = "plan",
    
    [Parameter(Mandatory=$false)]
    [string]$VarFile = "terraform.tfvars",
    
    [Parameter(Mandatory=$false)]
    [switch]$AutoApprove
)

Write-Host "🚀 Data Pipeline Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Check if Terraform is installed
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Terraform is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Terraform from: https://www.terraform.io/downloads.html" -ForegroundColor Yellow
    exit 1
}

# Check if AWS CLI is configured
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "⚠️  AWS CLI not found. Make sure it's installed and configured." -ForegroundColor Yellow
}

# Check if terraform.tfvars exists
if ($Action -ne "init" -and -not (Test-Path $VarFile)) {
    Write-Host "❌ $VarFile not found" -ForegroundColor Red
    Write-Host "Please copy terraform.tfvars.example to terraform.tfvars and configure it" -ForegroundColor Yellow
    exit 1
}

switch ($Action) {
    "init" {
        Write-Host "🔧 Initializing Terraform..." -ForegroundColor Green
        terraform init
    }
    
    "plan" {
        Write-Host "📋 Planning infrastructure changes..." -ForegroundColor Green
        terraform plan -var-file=$VarFile
    }
    
    "apply" {
        Write-Host "🏗️  Applying infrastructure changes..." -ForegroundColor Green
        if ($AutoApprove) {
            terraform apply -var-file=$VarFile -auto-approve
        } else {
            terraform apply -var-file=$VarFile
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Infrastructure deployed successfully!" -ForegroundColor Green
            Write-Host "📊 Getting outputs..." -ForegroundColor Cyan
            terraform output
        }
    }
    
    "destroy" {
        Write-Host "💥 Destroying infrastructure..." -ForegroundColor Red
        Write-Host "⚠️  This will permanently delete all resources!" -ForegroundColor Yellow
        
        if (-not $AutoApprove) {
            $confirm = Read-Host "Are you sure you want to destroy all resources? (yes/no)"
            if ($confirm -ne "yes") {
                Write-Host "❌ Destruction cancelled" -ForegroundColor Yellow
                exit 0
            }
        }
        
        terraform destroy -var-file=$VarFile -auto-approve
    }
    
    "output" {
        Write-Host "📊 Infrastructure outputs:" -ForegroundColor Green
        terraform output
    }
}

Write-Host "✅ Operation completed!" -ForegroundColor Green