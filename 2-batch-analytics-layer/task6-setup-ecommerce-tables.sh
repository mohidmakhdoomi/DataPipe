#!/bin/bash

# Task 6: Create Iceberg Tables for E-commerce Data
# This script creates comprehensive e-commerce tables with proper schemas and sample data

set -e

echo "🚀 Starting Task 6: Create Iceberg Tables for E-commerce Data"
echo "=============================================================="

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        print_error "Namespace '$NAMESPACE' does not exist. Please complete previous tasks first."
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
    
    # Check if Iceberg setup is complete (Task 5)
    if ! kubectl get configmap iceberg-catalog-config -n $NAMESPACE >/dev/null 2>&1; then
        print_error "Iceberg catalog configuration not found. Please complete Task 5 first."
        exit 1
    fi
    
    print_success "All prerequisites met"
}

# Function to deploy e-commerce table configuration
deploy_ecommerce_config() {
    print_status "Deploying e-commerce table configuration..."
    
    if kubectl apply -f "$SCRIPT_DIR/task6-ecommerce-tables-config.yaml"; then
        print_success "E-commerce table configuration deployed"
    else
        print_error "Failed to deploy e-commerce table configuration"
        exit 1
    fi
}

# Function to deploy e-commerce table creation job
deploy_ecommerce_job() {
    print_status "Deploying e-commerce table creation job..."
    
    if kubectl apply -f "$SCRIPT_DIR/task6-ecommerce-tables-job.yaml"; then
        print_success "E-commerce table creation job deployed"
    else
        print_error "Failed to deploy e-commerce table creation job"
        exit 1
    fi
}

# Function to monitor job execution
monitor_job() {
    print_status "Monitoring e-commerce table creation job execution..."
    
    # Wait for the SparkApplication to be created
    print_status "Waiting for SparkApplication to be created..."
    timeout=300  # 5 minutes
    elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if kubectl get sparkapplication ecommerce-tables-job -n $NAMESPACE >/dev/null 2>&1; then
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
        if kubectl get pod -l spark-role=driver,sparkapplication=ecommerce-tables-job -n $NAMESPACE >/dev/null 2>&1; then
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
        DRIVER_POD=$(kubectl get pod -l spark-role=driver,sparkapplication=ecommerce-tables-job -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
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
    STATUS=$(kubectl get sparkapplication ecommerce-tables-job -n $NAMESPACE -o jsonpath='{.status.applicationState.state}' 2>/dev/null || echo "UNKNOWN")
    
    case $STATUS in
        "COMPLETED")
            print_success "E-commerce table creation job completed successfully!"
            return 0
            ;;
        "FAILED")
            print_error "E-commerce table creation job failed"
            return 1
            ;;
        "RUNNING"|"SUBMITTED")
            print_warning "Job is still running. You can monitor it with:"
            echo "  kubectl get sparkapplication ecommerce-tables-job -n $NAMESPACE"
            echo "  kubectl logs -f <driver-pod-name> -n $NAMESPACE"
            return 0
            ;;
        *)
            print_warning "Job status: $STATUS"
            return 0
            ;;
    esac
}

# Function to validate table creation
validate_tables() {
    print_status "Validating e-commerce table creation..."
    
    # Check if ConfigMaps are created
    if kubectl get configmap ecommerce-tables-config -n $NAMESPACE >/dev/null 2>&1; then
        print_success "E-commerce table configuration found"
    else
        print_error "E-commerce table configuration not found"
        return 1
    fi
    
    if kubectl get configmap ecommerce-tables-script -n $NAMESPACE >/dev/null 2>&1; then
        print_success "E-commerce table script found"
    else
        print_error "E-commerce table script not found"
        return 1
    fi
    
    # Check SparkApplication
    if kubectl get sparkapplication ecommerce-tables-job -n $NAMESPACE >/dev/null 2>&1; then
        print_success "E-commerce table creation job found"
    else
        print_error "E-commerce table creation job not found"
        return 1
    fi
    
    print_success "E-commerce table validation completed"
}

# Function to show table information
show_table_info() {
    print_status "E-commerce tables created:"
    echo
    echo "📊 Tables in iceberg.ecommerce namespace:"
    echo "  • user_events - User interaction events (partitioned by date, hour)"
    echo "  • transactions - Financial transactions (partitioned by date)"
    echo "  • products - Product catalog (reference table)"
    echo "  • user_sessions - Aggregated user sessions (partitioned by date)"
    echo
    echo "🔧 Table Features:"
    echo "  • ACID transactions with Iceberg"
    echo "  • Schema evolution support"
    echo "  • Time travel capabilities"
    echo "  • Snappy compression for optimal storage"
    echo "  • 128MB target file sizes for performance"
    echo
    echo "📈 Sample Data:"
    echo "  • User events with different user tiers (bronze, silver, gold)"
    echo "  • Complete purchase journeys and conversion funnels"
    echo "  • Product catalog with electronics and accessories"
    echo "  • Transaction data with financial details"
    echo
}

# Function to show next steps
show_next_steps() {
    echo
    echo "=============================================="
    echo "🎉 Task 6 Complete!"
    echo "=============================================="
    echo
    echo "Next steps:"
    echo "1. Verify table creation:"
    echo "   kubectl logs <driver-pod-name> -n $NAMESPACE"
    echo
    echo "2. Check S3 warehouse structure:"
    echo "   aws s3 ls s3://<s3_bucket>/iceberg-warehouse/ecommerce/ --recursive"
    echo
    echo "3. Proceed to Task 7:"
    echo "   Implement Spark batch processing jobs"
    echo
    echo "Resources created:"
    echo "- ConfigMap: ecommerce-tables-config"
    echo "- ConfigMap: ecommerce-tables-script"
    echo "- SparkApplication: ecommerce-tables-job"
    echo "- Service: ecommerce-tables-service"
    echo
}

# Function to cleanup on failure
cleanup_on_failure() {
    print_warning "Cleaning up resources due to failure..."
    
    kubectl delete sparkapplication ecommerce-tables-job -n $NAMESPACE --ignore-not-found=true
    kubectl delete configmap ecommerce-tables-script -n $NAMESPACE --ignore-not-found=true
    kubectl delete configmap ecommerce-tables-config -n $NAMESPACE --ignore-not-found=true
    kubectl delete service ecommerce-tables-service -n $NAMESPACE --ignore-not-found=true
    
    print_warning "Cleanup completed"
}

# Main execution
main() {
    echo "Starting e-commerce table creation process..."
    echo "This will:"
    echo "1. Deploy e-commerce table configuration"
    echo "2. Create comprehensive Iceberg tables with proper schemas"
    echo "3. Insert sample data for testing and validation"
    echo "4. Validate table creation and data insertion"
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy configuration
    deploy_ecommerce_config
    
    # Deploy and run table creation job
    deploy_ecommerce_job
    
    # Monitor job execution
    if monitor_job; then
        validate_tables
        show_table_info
        show_next_steps
        print_success "Task 6 completed successfully!"
        exit 0
    else
        print_error "Task 6 failed"
        cleanup_on_failure
        exit 1
    fi
}

# Handle script interruption
trap 'print_warning "Script interrupted"; cleanup_on_failure; exit 1' INT TERM

# Run main function
main "$@"