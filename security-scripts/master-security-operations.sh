#!/bin/bash
# master-security-operations.sh
# Master script for data ingestion pipeline security operations

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="data-ingestion"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to show usage
show_usage() {
    echo "Data Ingestion Pipeline Security Operations"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  validate-all          Run all validation checks"
    echo "  validate-rbac         Validate RBAC configuration"
    echo "  validate-network      Validate network policies"
    echo "  validate-cdc          Validate CDC user permissions"
    echo "  daily-check           Run daily security check"
    echo "  rotate-postgresql     Rotate PostgreSQL CDC credentials"
    echo "  rotate-schema-registry Rotate Schema Registry credentials"
    echo "  emergency-lockdown    Emergency security lockdown"
    echo "  status               Show security status overview"
    echo ""
    echo "Options:"
    echo "  -h, --help           Show this help message"
    echo "  -v, --verbose        Verbose output"
    echo "  -n, --namespace      Kubernetes namespace (default: data-ingestion)"
    echo ""
    echo "Examples:"
    echo "  $0 validate-all"
    echo "  $0 rotate-postgresql"
    echo "  $0 daily-check"
    echo "  $0 emergency-lockdown"
}

# Function to check prerequisites
check_prerequisites() {
    print_status $BLUE "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_status $RED "ERROR: kubectl not found"
        exit 1
    fi
    
    # Check cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        print_status $RED "ERROR: Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        print_status $RED "ERROR: Namespace '$NAMESPACE' not found"
        exit 1
    fi
    
    # Check required tools
    for tool in jq base64 openssl; do
        if ! command -v $tool &> /dev/null; then
            print_status $RED "ERROR: Required tool '$tool' not found"
            exit 1
        fi
    done
    
    print_status $GREEN "✓ Prerequisites check passed"
}

# Function to validate all security configurations
validate_all() {
    print_status $BLUE "=== Running Complete Security Validation ==="
    
    print_status $YELLOW "1. Validating RBAC configuration..."
    bash "$SCRIPT_DIR/validate-rbac.sh"
    
    print_status $YELLOW "2. Validating network policies..."
    bash "$SCRIPT_DIR/validate-network-policies.sh"
    
    print_status $YELLOW "3. Validating CDC permissions..."
    bash "$SCRIPT_DIR/validate-cdc-permissions.sh"
    
    print_status $YELLOW "4. Running daily security check..."
    bash "$SCRIPT_DIR/daily-security-check.sh"
    
    print_status $GREEN "=== Complete security validation finished ==="
}

# Function to show security status overview
show_status() {
    print_status $BLUE "=== Data Ingestion Pipeline Security Status ==="
    
    # Check pod status
    print_status $YELLOW "Pod Status:"
    kubectl get pods -n $NAMESPACE -o wide
    
    echo ""
    
    # Check secrets
    print_status $YELLOW "Secrets Status:"
    kubectl get secrets -n $NAMESPACE
    
    echo ""
    
    # Check network policies
    print_status $YELLOW "Network Policies:"
    kubectl get networkpolicies -n $NAMESPACE
    
    echo ""
    
    # Check service accounts
    print_status $YELLOW "Service Accounts:"
    kubectl get serviceaccounts -n $NAMESPACE
    
    echo ""
    
    # Check recent security events
    print_status $YELLOW "Recent Security Events (last 1 hour):"
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10
}

# Function for emergency security lockdown
emergency_lockdown() {
    print_status $RED "=== EMERGENCY SECURITY LOCKDOWN ==="
    print_status $YELLOW "This will:"
    print_status $YELLOW "1. Scale down all data ingestion components"
    print_status $YELLOW "2. Rotate all credentials"
    print_status $YELLOW "3. Apply strictest network policies"
    print_status $YELLOW "4. Collect forensic logs"
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        print_status $YELLOW "Lockdown cancelled"
        exit 0
    fi
    
    print_status $RED "Initiating emergency lockdown..."
    
    # Scale down components
    print_status $YELLOW "Scaling down components..."
    kubectl scale deployment kafka-connect --replicas=0 -n $NAMESPACE
    kubectl scale deployment schema-registry --replicas=0 -n $NAMESPACE
    kubectl scale statefulset kafka --replicas=0 -n $NAMESPACE
    
    # Collect logs before shutdown
    print_status $YELLOW "Collecting forensic logs..."
    LOG_DIR="/tmp/emergency-logs-$(date +%Y%m%d-%H%M%S)"
    mkdir -p $LOG_DIR
    
    kubectl logs -n $NAMESPACE statefulset/postgresql --since=24h > $LOG_DIR/postgresql.log 2>/dev/null || true
    kubectl logs -n $NAMESPACE deployment/kafka-connect --since=24h > $LOG_DIR/kafka-connect.log 2>/dev/null || true
    kubectl logs -n $NAMESPACE deployment/schema-registry --since=24h > $LOG_DIR/schema-registry.log 2>/dev/null || true
    kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' > $LOG_DIR/events.log
    
    print_status $GREEN "Forensic logs collected in: $LOG_DIR"
    
    # Rotate credentials
    print_status $YELLOW "Rotating all credentials..."
    bash "$SCRIPT_DIR/rotate-postgresql-credentials.sh" || true
    bash "$SCRIPT_DIR/rotate-schema-registry-credentials.sh" || true
    
    print_status $RED "=== EMERGENCY LOCKDOWN COMPLETE ==="
    print_status $YELLOW "Components are scaled down and credentials rotated"
    print_status $YELLOW "Review logs in: $LOG_DIR"
    print_status $YELLOW "Manual intervention required to restore services"
}

# Function to make scripts executable
make_scripts_executable() {
    chmod +x "$SCRIPT_DIR"/*.sh
}

# Main script logic
main() {
    # Parse command line arguments
    VERBOSE=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            validate-all)
                COMMAND="validate-all"
                shift
                ;;
            validate-rbac)
                COMMAND="validate-rbac"
                shift
                ;;
            validate-network)
                COMMAND="validate-network"
                shift
                ;;
            validate-cdc)
                COMMAND="validate-cdc"
                shift
                ;;
            daily-check)
                COMMAND="daily-check"
                shift
                ;;
            rotate-postgresql)
                COMMAND="rotate-postgresql"
                shift
                ;;
            rotate-schema-registry)
                COMMAND="rotate-schema-registry"
                shift
                ;;
            emergency-lockdown)
                COMMAND="emergency-lockdown"
                shift
                ;;
            status)
                COMMAND="status"
                shift
                ;;
            *)
                print_status $RED "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show usage if no command provided
    if [ -z "${COMMAND:-}" ]; then
        show_usage
        exit 1
    fi
    
    # Make scripts executable
    make_scripts_executable
    
    # Check prerequisites
    check_prerequisites
    
    # Execute command
    case $COMMAND in
        validate-all)
            validate_all
            ;;
        validate-rbac)
            bash "$SCRIPT_DIR/validate-rbac.sh"
            ;;
        validate-network)
            bash "$SCRIPT_DIR/validate-network-policies.sh"
            ;;
        validate-cdc)
            bash "$SCRIPT_DIR/validate-cdc-permissions.sh"
            ;;
        daily-check)
            bash "$SCRIPT_DIR/daily-security-check.sh"
            ;;
        rotate-postgresql)
            bash "$SCRIPT_DIR/rotate-postgresql-credentials.sh"
            ;;
        rotate-schema-registry)
            bash "$SCRIPT_DIR/rotate-schema-registry-credentials.sh"
            ;;
        emergency-lockdown)
            emergency_lockdown
            ;;
        status)
            show_status
            ;;
        *)
            print_status $RED "Unknown command: $COMMAND"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"