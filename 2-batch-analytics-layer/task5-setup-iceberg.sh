#!/bin/bash

# Task 5: Set up Apache Iceberg on S3 for Data Lake
# This script configures Iceberg catalog, creates tables, and tests functionality

set -e

echo "🚀 Starting Task 5: Apache Iceberg Setup on S3"
echo "=============================================="

# Configuration
readonly NAMESPACE="batch-analytics"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if namespace exists
check_namespace() {
    if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        print_success "Namespace '$NAMESPACE' exists"
        return 0
    else
        print_error "Namespace '$NAMESPACE' does not exist"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if namespace exists
    if ! check_namespace; then
        print_error "Required namespace not found. Please run tasks 1-4 first."
        exit 1
    fi
    
    # Check if AWS S3 credentials exist
    if ! kubectl get secret aws-s3-credentials -n $NAMESPACE >/dev/null 2>&1; then
        print_error "AWS S3 credentials secret not found. Please complete Task 3 first."
        exit 1
    fi
    
    # Check if Spark Operator is running
    if ! kubectl get deployment batch-analytics-spark-operator-controller -n $NAMESPACE >/dev/null 2>&1; then
        print_error "Spark Operator not found. Please complete Task 2 first."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to deploy Iceberg configuration
deploy_iceberg_config() {
    print_status "Deploying Iceberg catalog configuration..."
    
    if kubectl apply -f "$SCRIPT_DIR/task5-iceberg-catalog-config.yaml"; then
        print_success "Iceberg catalog configuration deployed"
    else
        print_error "Failed to deploy Iceberg catalog configuration"
        exit 1
    fi
    
    # # Wait for ConfigMap to be ready
    # print_status "Waiting for ConfigMap to be ready..."
    # kubectl wait --for=condition=Ready configmap/iceberg-catalog-config -n $NAMESPACE --timeout=60s || true
}

# Function to deploy Iceberg setup job
deploy_iceberg_setup_job() {
    print_status "Deploying Iceberg setup and test job..."
    
    if kubectl apply -f "$SCRIPT_DIR/task5-iceberg-setup-job.yaml"; then
        print_success "Iceberg setup job deployed"
    else
        print_error "Failed to deploy Iceberg setup job"
        exit 1
    fi
}

# Function to monitor job execution
monitor_job() {
    print_status "Monitoring Iceberg setup job execution..."
    
    # Wait for the SparkApplication to be created
    print_status "Waiting for SparkApplication to be created..."
    timeout=300  # 5 minutes
    elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get sparkapplication iceberg-setup-job -n $NAMESPACE >/dev/null 2>&1; then
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    echo
    
    if [ $elapsed -ge $timeout ]; then
        print_error "Timeout waiting for SparkApplication to be created"
        return 1
    fi
    
    print_success "SparkApplication created successfully"
    
    # Monitor the job status
    print_status "Monitoring job progress (this may take 5-10 minutes)..."
    
    # Wait for driver pod to be created
    print_status "Waiting for driver pod to be created..."
    timeout=300  # 5 minutes
    elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get pod -l spark-role=driver,sparkapplication=iceberg-setup-job -n $NAMESPACE >/dev/null 2>&1; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        printf "."
    done
    echo
    
    if [ $elapsed -ge $timeout ]; then
        print_warning "Driver pod not found within timeout, but job may still be running"
    else
        print_success "Driver pod created"
        
        # Get driver pod name
        DRIVER_POD=$(kubectl get pod -l spark-role=driver,sparkapplication=iceberg-setup-job -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$DRIVER_POD" ]; then
            print_status "Driver pod: $DRIVER_POD"
            
            # Follow logs for a while
            print_status "Following job logs (press Ctrl+C to stop following, job will continue)..."
            timeout 300 kubectl logs -f "$DRIVER_POD" -n $NAMESPACE || true
        fi
    fi
    
    # Check final job status
    print_status "Checking final job status..."
    
    # Wait a bit more for job completion
    sleep 30
    
    # Get SparkApplication status
    STATUS=$(kubectl get sparkapplication iceberg-setup-job -n $NAMESPACE -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "UNKNOWN")
    
    case $STATUS in
        "COMPLETED")
            print_success "Iceberg setup job completed successfully!"
            return 0
            ;;
        "FAILED")
            print_error "Iceberg setup job failed"
            return 1
            ;;
        "RUNNING"|"SUBMITTED")
            print_warning "Job is still running. You can monitor it with:"
            echo "  kubectl get sparkapplication iceberg-setup-job -n $NAMESPACE"
            echo "  kubectl logs -f <driver-pod-name> -n $NAMESPACE"
            return 0
            ;;
        *)
            print_warning "Job status: $STATUS"
            return 0
            ;;
    esac
}

# Function to validate setup
validate_setup() {
    print_status "Validating Iceberg setup..."
    
    # Check if ConfigMaps are created
    if kubectl get configmap iceberg-catalog-config -n $NAMESPACE >/dev/null 2>&1; then
        print_success "Iceberg catalog configuration found"
    else
        print_error "Iceberg catalog configuration not found"
        return 1
    fi
    
    if kubectl get configmap iceberg-setup-script -n $NAMESPACE >/dev/null 2>&1; then
        print_success "Iceberg setup script found"
    else
        print_error "Iceberg setup script not found"
        return 1
    fi
    
    # Check SparkApplication
    if kubectl get sparkapplication iceberg-setup-job -n $NAMESPACE >/dev/null 2>&1; then
        print_success "Iceberg setup job found"
    else
        print_error "Iceberg setup job not found"
        return 1
    fi
    
    print_success "Iceberg setup validation completed"
}

# Function to show next steps
show_next_steps() {
    echo
    echo "=============================================="
    echo "🎉 Task 5 Setup Complete!"
    echo "=============================================="
    echo
    echo "Next steps:"
    echo "1. Monitor the job completion:"
    echo "   kubectl get sparkapplication iceberg-setup-job -n $NAMESPACE"
    echo
    echo "2. Check job logs:"
    echo "   kubectl logs -f <driver-pod-name> -n $NAMESPACE"
    echo
    echo "3. Verify S3 bucket contents:"
    echo "   aws s3 ls s3://data-s3-bucket/iceberg-warehouse/ --recursive"
    echo
    echo "4. Once job completes successfully, proceed to Task 6:"
    echo "   Create Iceberg tables for e-commerce data"
    echo
    echo "Resources created:"
    echo "- ConfigMap: iceberg-catalog-config"
    echo "- ConfigMap: iceberg-setup-script"
    echo "- SparkApplication: iceberg-setup-job"
    echo
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_warning "Cleaning up resources due to failure..."
    
    kubectl delete sparkapplication iceberg-setup-job -n $NAMESPACE --ignore-not-found=true
    kubectl delete configmap iceberg-setup-script -n $NAMESPACE --ignore-not-found=true
    kubectl delete configmap iceberg-catalog-config -n $NAMESPACE --ignore-not-found=true
    
    print_warning "Cleanup completed"
}

# Main execution
main() {
    echo "Starting Apache Iceberg setup process..."
    echo "This will:"
    echo "1. Deploy Iceberg catalog configuration"
    echo "2. Create and run comprehensive setup job"
    echo "3. Test ACID operations and schema evolution"
    echo "4. Validate time travel capabilities"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy configuration
    deploy_iceberg_config
    
    # Deploy and run setup job
    deploy_iceberg_setup_job
    
    # Monitor job execution
    if monitor_job; then
        validate_setup
        show_next_steps
        print_success "Task 5 setup completed successfully!"
        exit 0
    else
        print_error "Task 5 setup failed"
        cleanup_on_failure
        exit 1
    fi
}

# Handle script interruption
trap 'print_warning "Script interrupted"; cleanup_on_failure; exit 1' INT TERM

# Run main function
main "$@"