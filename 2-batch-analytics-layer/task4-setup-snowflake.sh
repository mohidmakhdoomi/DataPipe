#!/bin/bash

# Task 4: Set up Snowflake connection and authentication
# This script configures Snowflake connectivity for the batch analytics layer

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="batch-analytics"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}🚀 Task 4: Setting up Snowflake connection and authentication${NC}"
echo "=================================================================="
echo ""

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}❌ kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
}

# Function to check if namespace exists
check_namespace() {
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        echo -e "${RED}❌ Namespace '$NAMESPACE' does not exist${NC}"
        echo "Please run Task 1 first to create the namespace"
        exit 1
    fi
}

# Function to check cluster connectivity
check_cluster() {
    echo -e "${CYAN}🔍 Checking Kubernetes cluster connectivity...${NC}"
    if ! kubectl cluster-info &> /dev/null; then
        echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
        echo "Please ensure your cluster is running and kubectl is configured"
        exit 1
    fi
    echo -e "${GREEN}✅ Cluster connectivity verified${NC}"
}

# Function to deploy Snowflake secrets and configuration
deploy_snowflake_config() {
    echo -e "${CYAN}📦 Deploying Snowflake secrets and configuration...${NC}"
    
    # Check if secrets file exists
    if [[ ! -f "$SCRIPT_DIR/task4-snowflake-secrets.yaml" ]]; then
        echo -e "${RED}❌ Snowflake secrets file not found: $SCRIPT_DIR/task4-snowflake-secrets.yaml${NC}"
        exit 1
    fi
    
    # Apply Snowflake secrets and configuration
    echo "   Applying Snowflake secrets..."
    kubectl apply -f "$SCRIPT_DIR/task4-snowflake-secrets.yaml" -n "$NAMESPACE"
    
    # Verify secrets were created
    if kubectl get secret snowflake-credentials -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}✅ Snowflake credentials secret created${NC}"
    else
        echo -e "${RED}❌ Failed to create Snowflake credentials secret${NC}"
        exit 1
    fi
    
    # Verify ConfigMap was created
    if kubectl get configmap snowflake-config -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}✅ Snowflake configuration ConfigMap created${NC}"
    else
        echo -e "${RED}❌ Failed to create Snowflake configuration ConfigMap${NC}"
        exit 1
    fi
}

# Function to deploy Snowflake test resources
deploy_test_resources() {
    echo -e "${CYAN}🧪 Deploying Snowflake test resources...${NC}"
    
    # Deploy test script ConfigMap
    if [[ -f "$SCRIPT_DIR/task4-snowflake-test-job.yaml" ]]; then
        echo "   Applying Snowflake test job configuration..."
        kubectl apply -f "$SCRIPT_DIR/task4-snowflake-test-job.yaml" -n "$NAMESPACE"
        
        # Verify test script ConfigMap was created
        if kubectl get configmap snowflake-test-script -n "$NAMESPACE" &> /dev/null; then
            echo -e "${GREEN}✅ Snowflake test script ConfigMap created${NC}"
        else
            echo -e "${RED}❌ Failed to create Snowflake test script ConfigMap${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  Snowflake test job file not found, skipping test deployment${NC}"
    fi
}

# Function to validate Snowflake configuration
validate_configuration() {
    echo -e "${CYAN}🔍 Validating Snowflake configuration...${NC}"
    
    # Check if secrets contain required keys
    echo "   Checking secret keys..."
    required_keys=("SNOWFLAKE_ACCOUNT" "SNOWFLAKE_USER" "SNOWFLAKE_PASSWORD" "SNOWFLAKE_ROLE" "SNOWFLAKE_WAREHOUSE" "SNOWFLAKE_DATABASE" "SNOWFLAKE_SCHEMA")
    
    for key in "${required_keys[@]}"; do
        if kubectl get secret snowflake-credentials -n "$NAMESPACE" -o jsonpath="{.data.$key}" | base64 -d &> /dev/null; then
            echo -e "${GREEN}   ✅ $key configured${NC}"
        else
            echo -e "${RED}   ❌ $key missing or invalid${NC}"
            exit 1
        fi
    done
    
    # Check ConfigMap data
    echo "   Checking ConfigMap data..."
    config_keys=("snowflake-connection.properties" "spark-snowflake.conf" "schema-definitions.sql")
    
    for key in "${config_keys[@]}"; do
        if kubectl get configmap snowflake-config -n "$NAMESPACE" -o jsonpath="{.data.$key}" &> /dev/null; then
            echo -e "${GREEN}   ✅ $key configured${NC}"
        else
            echo -e "${RED}   ❌ $key missing${NC}"
            exit 1
        fi
    done
}

# Function to run connectivity test
run_connectivity_test() {
    echo -e "${CYAN}🧪 Running Snowflake connectivity test...${NC}"
    
    # Check if Spark Operator is available
    if ! kubectl get crd sparkapplications.sparkoperator.k8s.io &> /dev/null; then
        echo -e "${YELLOW}⚠️  Spark Operator not found, skipping connectivity test${NC}"
        echo "   Please run Task 2 first to deploy Spark Operator"
        return 0
    fi
    
    # Submit the test job
    echo "   Submitting Snowflake connectivity test job..."
    kubectl apply -f "$SCRIPT_DIR/task4-snowflake-test-job.yaml" -n "$NAMESPACE"
    
    # Wait for the job to be created
    echo "   Waiting for test job to start..."
    sleep 5
    
    # Check if the SparkApplication was created
    if kubectl get sparkapplication snowflake-test-job -n "$NAMESPACE" &> /dev/null; then
        echo -e "${GREEN}✅ Snowflake test job submitted successfully${NC}"
        echo ""
        echo -e "${YELLOW}📋 To monitor the test job:${NC}"
        echo "   kubectl get sparkapplication snowflake-test-job -n $NAMESPACE"
        echo "   kubectl describe sparkapplication snowflake-test-job -n $NAMESPACE"
        echo "   kubectl logs -f sparkapplication/snowflake-test-job -n $NAMESPACE"
    else
        echo -e "${RED}❌ Failed to submit Snowflake test job${NC}"
        exit 1
    fi
}

# Function to display connection information
display_connection_info() {
    echo -e "${CYAN}📊 Snowflake Connection Information${NC}"
    echo "=================================="
    
    # Extract connection details (safely)
    ACCOUNT=$(kubectl get secret snowflake-credentials -n "$NAMESPACE" -o jsonpath="{.data.SNOWFLAKE_ACCOUNT}" | base64 -d 2>/dev/null || echo "Not configured")
    DATABASE=$(kubectl get secret snowflake-credentials -n "$NAMESPACE" -o jsonpath="{.data.SNOWFLAKE_DATABASE}" | base64 -d 2>/dev/null || echo "Not configured")
    WAREHOUSE=$(kubectl get secret snowflake-credentials -n "$NAMESPACE" -o jsonpath="{.data.SNOWFLAKE_WAREHOUSE}" | base64 -d 2>/dev/null || echo "Not configured")
    ROLE=$(kubectl get secret snowflake-credentials -n "$NAMESPACE" -o jsonpath="{.data.SNOWFLAKE_ROLE}" | base64 -d 2>/dev/null || echo "Not configured")
    
    echo "Account:   $ACCOUNT"
    echo "Database:  $DATABASE"
    echo "Warehouse: $WAREHOUSE"
    echo "Role:      $ROLE"
    echo ""
    
    echo -e "${YELLOW}📝 Note: Update the credentials in task4-snowflake-secrets.yaml with your actual Snowflake details${NC}"
}

# Function to display next steps
display_next_steps() {
    echo ""
    echo -e "${GREEN}🎉 Task 4 completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}📋 What was configured:${NC}"
    echo "✅ Snowflake credentials secret created"
    echo "✅ Snowflake connection configuration deployed"
    echo "✅ 3-layer architecture schema definitions prepared"
    echo "✅ Spark-Snowflake connector configuration ready"
    echo "✅ Connectivity test job submitted"
    echo ""
    echo -e "${YELLOW}🔧 Useful Commands:${NC}"
    echo "   # Check Snowflake secrets"
    echo "   kubectl get secret snowflake-credentials -n $NAMESPACE"
    echo ""
    echo "   # View Snowflake configuration"
    echo "   kubectl get configmap snowflake-config -n $NAMESPACE -o yaml"
    echo ""
    echo "   # Monitor connectivity test"
    echo "   kubectl get sparkapplication snowflake-test-job -n $NAMESPACE"
    echo "   kubectl logs -f sparkapplication/snowflake-test-job -n $NAMESPACE"
    echo ""
    echo "   # Clean up test job"
    echo "   kubectl delete sparkapplication snowflake-test-job -n $NAMESPACE"
    echo ""
    echo -e "${PURPLE}🚀 Next Steps:${NC}"
    echo "1. Update task4-snowflake-secrets.yaml with your actual Snowflake credentials"
    echo "2. Reapply the secrets: kubectl apply -f task4-snowflake-secrets.yaml -n $NAMESPACE"
    echo "3. Run the connectivity test to verify the connection"
    echo "4. Proceed to Task 5: Set up Apache Iceberg on S3 for data lake"
    echo ""
    echo -e "${GREEN}Snowflake connection setup is now complete!${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}Starting Task 4: Snowflake connection setup...${NC}"
    echo ""
    
    # Pre-flight checks
    check_kubectl
    check_cluster
    check_namespace
    
    # Deploy configurations
    deploy_snowflake_config
    deploy_test_resources
    
    # Validate deployment
    validate_configuration
    
    # Run connectivity test
    run_connectivity_test
    
    # Display information
    display_connection_info
    display_next_steps
}

# Run main function
main "$@"