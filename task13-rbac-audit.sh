#!/bin/bash
# Task 13: Kubernetes RBAC Audit
# Validates service account permissions follow least privilege

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-data-ingestion}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Kubernetes RBAC Audit ==="
echo "Namespace: $NAMESPACE"
echo

# Function to check if namespace exists
check_namespace() {
    local ns=$1
    echo -n "Checking namespace '$ns'... "
    
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ EXISTS${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        return 1
    fi
}

# Function to list service accounts
list_service_accounts() {
    local ns=$1
    echo "Service accounts in namespace '$ns':"
    
    local service_accounts=$(kubectl get serviceaccount -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$service_accounts" ]; then
        echo -e "${YELLOW}⚠ NO SERVICE ACCOUNTS FOUND${NC}"
        return 1
    else
        for sa in $service_accounts; do
            if [ "$sa" != "default" ]; then
                echo -e "  ${GREEN}✓${NC} $sa"
            else
                echo -e "  ${BLUE}•${NC} $sa (default)"
            fi
        done
        return 0
    fi
}

# Function to analyze service account permissions
analyze_service_account() {
    local ns=$1
    local sa=$2
    
    echo "Analyzing service account: $sa"
    
    # Check if service account exists
    if ! kubectl get serviceaccount "$sa" -n "$ns" >/dev/null 2>&1; then
        echo -e "  ${RED}✗ Service account not found${NC}"
        return 1
    fi
    
    # Check automountServiceAccountToken
    echo -n "  - Auto-mount token: "
    local automount=$(kubectl get serviceaccount "$sa" -n "$ns" -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null || echo "null")
    
    case "$automount" in
        "false")
            echo -e "${GREEN}✓ DISABLED${NC}"
            ;;
        "true"|"null")
            echo -e "${YELLOW}⚠ ENABLED${NC}"
            echo "    Recommendation: Disable if not needed for security"
            ;;
        *)
            echo -e "${YELLOW}⚠ UNKNOWN: $automount${NC}"
            ;;
    esac
    
    # Find role bindings for this service account
    echo "  - Role bindings:"
    local bindings_found=false
    
    # Check cluster role bindings
    local cluster_bindings=$(kubectl get clusterrolebinding -o json | jq -r --arg sa "$sa" --arg ns "$ns" '.items[] | select(.subjects[]? | select(.kind=="ServiceAccount" and .name==$sa and .namespace==$ns)) | .metadata.name' 2>/dev/null || echo "")
    
    if [ -n "$cluster_bindings" ]; then
        for binding in $cluster_bindings; do
            local role=$(kubectl get clusterrolebinding "$binding" -o jsonpath='{.roleRef.name}')
            echo -e "    ${YELLOW}⚠ ClusterRoleBinding:${NC} $binding → $role"
            bindings_found=true
            
            # Analyze cluster role permissions
            analyze_cluster_role "$role"
        done
    fi
    
    # Check role bindings in namespace
    local role_bindings=$(kubectl get rolebinding -n "$ns" -o json | jq -r --arg sa "$sa" '.items[] | select(.subjects[]? | select(.kind=="ServiceAccount" and .name==$sa)) | .metadata.name' 2>/dev/null || echo "")
    
    if [ -n "$role_bindings" ]; then
        for binding in $role_bindings; do
            local role=$(kubectl get rolebinding "$binding" -n "$ns" -o jsonpath='{.roleRef.name}')
            local role_kind=$(kubectl get rolebinding "$binding" -n "$ns" -o jsonpath='{.roleRef.kind}')
            echo -e "    ${GREEN}✓ RoleBinding:${NC} $binding → $role ($role_kind)"
            bindings_found=true
            
            # Analyze role permissions
            if [ "$role_kind" = "Role" ]; then
                analyze_role "$ns" "$role"
            elif [ "$role_kind" = "ClusterRole" ]; then
                analyze_cluster_role "$role"
            fi
        done
    fi
    
    if [ "$bindings_found" = false ]; then
        echo -e "    ${GREEN}✓ NO BINDINGS${NC} (uses default permissions only)"
    fi
}

# Function to analyze role permissions
analyze_role() {
    local ns=$1
    local role=$2
    
    echo "    Role permissions for '$role':"
    
    if ! kubectl get role "$role" -n "$ns" >/dev/null 2>&1; then
        echo -e "      ${RED}✗ Role not found${NC}"
        return 1
    fi
    
    # Get role rules
    local rules=$(kubectl get role "$role" -n "$ns" -o json | jq -r '.rules[] | "\(.apiGroups // [""]) \(.resources // [""]) \(.verbs // [""])"' 2>/dev/null || echo "")
    
    if [ -z "$rules" ]; then
        echo -e "      ${GREEN}✓ NO RULES${NC}"
        return 0
    fi
    
    echo "$rules" | while IFS= read -r rule; do
        local api_groups=$(echo "$rule" | cut -d' ' -f1 | tr -d '[]"' | tr ',' ' ')
        local resources=$(echo "$rule" | cut -d' ' -f2 | tr -d '[]"' | tr ',' ' ')
        local verbs=$(echo "$rule" | cut -d' ' -f3 | tr -d '[]"' | tr ',' ' ')
        
        # Check for overly permissive rules
        if [[ "$resources" == *"*"* ]] || [[ "$verbs" == *"*"* ]]; then
            echo -e "      ${RED}⚠ OVERLY PERMISSIVE:${NC} $api_groups/$resources ($verbs)"
        else
            echo -e "      ${GREEN}✓${NC} $api_groups/$resources ($verbs)"
        fi
    done
}

# Function to analyze cluster role permissions
analyze_cluster_role() {
    local role=$1
    
    echo "    ClusterRole permissions for '$role':"
    
    if ! kubectl get clusterrole "$role" >/dev/null 2>&1; then
        echo -e "      ${RED}✗ ClusterRole not found${NC}"
        return 1
    fi
    
    # Get cluster role rules
    local rules=$(kubectl get clusterrole "$role" -o json | jq -r '.rules[] | "\(.apiGroups // [""]) \(.resources // [""]) \(.verbs // [""])"' 2>/dev/null || echo "")
    
    if [ -z "$rules" ]; then
        echo -e "      ${GREEN}✓ NO RULES${NC}"
        return 0
    fi
    
    echo "$rules" | while IFS= read -r rule; do
        local api_groups=$(echo "$rule" | cut -d' ' -f1 | tr -d '[]"' | tr ',' ' ')
        local resources=$(echo "$rule" | cut -d' ' -f2 | tr -d '[]"' | tr ',' ' ')
        local verbs=$(echo "$rule" | cut -d' ' -f3 | tr -d '[]"' | tr ',' ' ')
        
        # Check for overly permissive rules
        if [[ "$resources" == *"*"* ]] || [[ "$verbs" == *"*"* ]]; then
            echo -e "      ${RED}⚠ OVERLY PERMISSIVE:${NC} $api_groups/$resources ($verbs)"
        else
            echo -e "      ${GREEN}✓${NC} $api_groups/$resources ($verbs)"
        fi
    done
}

# Function to test specific permissions
test_permissions() {
    local ns=$1
    local sa=$2
    
    echo "Testing specific permissions for '$sa':"
    
    # Test common permissions that should be restricted
    local restricted_tests=(
        "create pods"
        "delete pods"
        "create secrets"
        "delete secrets"
        "create configmaps"
        "delete configmaps"
        "get secrets --all-namespaces"
    )
    
    for test in "${restricted_tests[@]}"; do
        echo -n "  - $test: "
        if kubectl auth can-i $test --as="system:serviceaccount:$ns:$sa" >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ ALLOWED${NC}"
        else
            echo -e "${GREEN}✓ DENIED${NC}"
        fi
    done
    
    # Test permissions that might be needed for data pipeline
    local pipeline_tests=(
        "get pods"
        "list pods"
        "get configmaps"
        "list configmaps"
        "get secrets"
        "list secrets"
    )
    
    echo "  Pipeline-specific permissions:"
    for test in "${pipeline_tests[@]}"; do
        echo -n "    - $test: "
        if kubectl auth can-i $test --as="system:serviceaccount:$ns:$sa" -n "$ns" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ ALLOWED${NC}"
        else
            echo -e "${YELLOW}⚠ DENIED${NC}"
        fi
    done
}

# Function to check for default service account usage
check_default_sa_usage() {
    local ns=$1
    
    echo "Checking for default service account usage:"
    
    local pods_using_default=$(kubectl get pods -n "$ns" -o json | jq -r '.items[] | select(.spec.serviceAccountName == "default" or (.spec.serviceAccountName == null)) | .metadata.name' 2>/dev/null || echo "")
    
    if [ -z "$pods_using_default" ]; then
        echo -e "  ${GREEN}✓ No pods using default service account${NC}"
    else
        echo -e "  ${YELLOW}⚠ Pods using default service account:${NC}"
        for pod in $pods_using_default; do
            echo "    - $pod"
        done
        echo "  Recommendation: Use dedicated service accounts for each component"
    fi
}

# Function to generate RBAC recommendations
generate_rbac_recommendations() {
    echo
    echo "=== RBAC Security Recommendations ==="
    echo
    echo "1. Service Account Best Practices:"
    echo "   - Create dedicated service accounts for each component"
    echo "   - Disable automountServiceAccountToken when not needed"
    echo "   - Avoid using the default service account"
    echo
    echo "2. Role-Based Access Control:"
    echo "   - Use Roles instead of ClusterRoles when possible"
    echo "   - Grant minimal required permissions only"
    echo "   - Avoid wildcard permissions (*) in resources and verbs"
    echo
    echo "3. Component-Specific Permissions:"
    echo "   - PostgreSQL: Minimal permissions (no Kubernetes API access needed)"
    echo "   - Kafka: Basic pod management permissions"
    echo "   - Schema Registry: ConfigMap access for configuration"
    echo "   - Kafka Connect: Secret and ConfigMap access for connectors"
    echo
    echo "4. Monitoring and Auditing:"
    echo "   - Regularly audit service account permissions"
    echo "   - Monitor for privilege escalation attempts"
    echo "   - Use admission controllers to enforce policies"
}

# Function to create example RBAC manifests
create_example_rbac() {
    local ns=$1
    
    echo "Example RBAC configuration for data pipeline:"
    
    cat << EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kafka-connect-sa
  namespace: $ns
automountServiceAccountToken: true
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $ns
  name: kafka-connect-role
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: kafka-connect-binding
  namespace: $ns
subjects:
- kind: ServiceAccount
  name: kafka-connect-sa
  namespace: $ns
roleRef:
  kind: Role
  name: kafka-connect-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: postgresql-sa
  namespace: $ns
automountServiceAccountToken: false
EOF
}

# Main audit
main() {
    local exit_code=0
    
    echo "Starting RBAC audit..."
    echo
    
    # Check namespace exists
    if ! check_namespace "$NAMESPACE"; then
        echo -e "${RED}ERROR: Namespace does not exist${NC}"
        exit 1
    fi
    
    echo
    
    # List service accounts
    if ! list_service_accounts "$NAMESPACE"; then
        exit_code=1
    fi
    
    echo
    
    # Analyze each service account
    local service_accounts=$(kubectl get serviceaccount -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        for sa in $service_accounts; do
            if [ "$sa" != "default" ]; then
                analyze_service_account "$NAMESPACE" "$sa"
                echo
                test_permissions "$NAMESPACE" "$sa"
                echo
            fi
        done
    fi
    
    # Check default service account usage
    check_default_sa_usage "$NAMESPACE"
    
    # Generate recommendations
    generate_rbac_recommendations
    
    echo
    echo "=== Example RBAC Configuration ==="
    create_example_rbac "$NAMESPACE"
    
    # Generate audit report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file="/tmp/rbac-audit-$timestamp.json"
    
    cat > "$report_file" << EOF
{
  "audit_type": "rbac",
  "timestamp": "$timestamp",
  "namespace": "$NAMESPACE",
  "status": $([ $exit_code -eq 0 ] && echo '"PASS"' || echo '"FAIL"'),
  "checks_performed": [
    "service_accounts_exist",
    "role_bindings_analysis",
    "permission_testing",
    "default_sa_usage_check"
  ],
  "service_accounts": [$(kubectl get serviceaccount -n "$NAMESPACE" -o jsonpath='{range .items[*]}"{.metadata.name}"{end}' 2>/dev/null | sed 's/""/, /g' | sed 's/, $//' || echo "")]
}
EOF
    
    echo
    echo "=== Audit Summary ==="
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ RBAC audit completed${NC}"
    else
        echo -e "${YELLOW}⚠ RBAC audit completed with warnings${NC}"
    fi
    echo "Audit report saved to: $report_file"
    
    exit $exit_code
}

# Run main function
main "$@"