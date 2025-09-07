#!/bin/bash
# Task 13: Network Policy Validation
# Tests network isolation between data pipeline components

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-data-ingestion}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Network Policy Validation ==="
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

# Function to list network policies
list_network_policies() {
    local ns=$1
    echo "Network policies in namespace '$ns':"
    
    local policies=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null || echo "")
    
    if [ -z "$policies" ]; then
        echo -e "${YELLOW}⚠ NO NETWORK POLICIES FOUND${NC}"
        echo "  This means all traffic is allowed by default"
        return 1
    else
        echo "$policies" | while read policy; do
            local policy_name=$(echo "$policy" | cut -d'/' -f2)
            echo -e "  ${GREEN}✓${NC} $policy_name"
        done
        return 0
    fi
}

# Function to analyze network policy
analyze_network_policy() {
    local ns=$1
    local policy_name=$2
    
    echo "Analyzing network policy: $policy_name"
    
    # Get policy details
    local policy_yaml="/tmp/netpol-$policy_name.yaml"
    kubectl get networkpolicy "$policy_name" -n "$ns" -o yaml > "$policy_yaml"
    
    # Check if policy has ingress rules
    echo -n "  - Ingress rules: "
    if grep -q "ingress:" "$policy_yaml"; then
        local ingress_count=$(grep -A 20 "ingress:" "$policy_yaml" | grep -c "- " || echo "0")
        echo -e "${GREEN}✓ $ingress_count rules${NC}"
    else
        echo -e "${YELLOW}⚠ NONE (denies all ingress)${NC}"
    fi
    
    # Check if policy has egress rules
    echo -n "  - Egress rules: "
    if grep -q "egress:" "$policy_yaml"; then
        local egress_count=$(grep -A 20 "egress:" "$policy_yaml" | grep -c "- " || echo "0")
        echo -e "${GREEN}✓ $egress_count rules${NC}"
    else
        echo -e "${YELLOW}⚠ NONE (denies all egress)${NC}"
    fi
    
    # Check pod selector
    echo -n "  - Pod selector: "
    local selector=$(kubectl get networkpolicy "$policy_name" -n "$ns" -o jsonpath='{.spec.podSelector}')
    if [ "$selector" = "{}" ]; then
        echo -e "${YELLOW}⚠ ALL PODS${NC}"
    else
        echo -e "${GREEN}✓ SPECIFIC PODS${NC}"
    fi
}

# Function to test network connectivity
test_network_connectivity() {
    local ns=$1
    
    echo "Testing network connectivity between components:"
    
    # Test PostgreSQL connectivity from Kafka Connect
    echo -n "  - Kafka Connect → PostgreSQL: "
    if test_connection_from_to "$ns" "app=kafka-connect" "postgresql.data-ingestion.svc.cluster.local" "5432"; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    else
        echo -e "${RED}✗ BLOCKED${NC}"
    fi
    
    # Test Kafka connectivity from Kafka Connect
    echo -n "  - Kafka Connect → Kafka: "
    if test_connection_from_to "$ns" "app=kafka-connect" "kafka-headless.data-ingestion.svc.cluster.local" "9092"; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    else
        echo -e "${RED}✗ BLOCKED${NC}"
    fi
    
    # Test Schema Registry connectivity from Kafka Connect
    echo -n "  - Kafka Connect → Schema Registry: "
    if test_connection_from_to "$ns" "app=kafka-connect" "schema-registry.data-ingestion.svc.cluster.local" "8081"; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    else
        echo -e "${RED}✗ BLOCKED${NC}"
    fi
    
    # Test Kafka connectivity from Schema Registry
    echo -n "  - Schema Registry → Kafka: "
    if test_connection_from_to "$ns" "app=schema-registry" "kafka-headless.data-ingestion.svc.cluster.local" "9092"; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    else
        echo -e "${RED}✗ BLOCKED${NC}"
    fi
    
    # Test external connectivity (should be allowed for S3)
    echo -n "  - Kafka Connect → External (S3): "
    if test_external_connectivity "$ns" "app=kafka-connect"; then
        echo -e "${GREEN}✓ ALLOWED${NC}"
    else
        echo -e "${RED}✗ BLOCKED${NC}"
    fi
}

# Function to test connection from one pod to another
test_connection_from_to() {
    local ns=$1
    local from_selector=$2
    local to_host=$3
    local to_port=$4
    
    # Get a pod matching the selector
    local from_pod=$(kubectl get pods -n "$ns" -l "$from_selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$from_pod" ]; then
        return 1
    fi
    
    # Test connection with timeout
    kubectl exec -n "$ns" "$from_pod" -- timeout 5 nc -z "$to_host" "$to_port" >/dev/null 2>&1
}

# Function to test external connectivity
test_external_connectivity() {
    local ns=$1
    local from_selector=$2
    
    # Get a pod matching the selector
    local from_pod=$(kubectl get pods -n "$ns" -l "$from_selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$from_pod" ]; then
        return 1
    fi
    
    # Test connection to AWS S3 (should work for S3 sink connector)
    kubectl exec -n "$ns" "$from_pod" -- timeout 5 nc -z s3.amazonaws.com 443 >/dev/null 2>&1
}

# Function to test DNS resolution
test_dns_resolution() {
    local ns=$1
    
    echo "Testing DNS resolution:"
    
    # Test from Kafka Connect pod
    local test_pod=$(kubectl get pods -n "$ns" -l "app=kafka-connect" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$test_pod" ]; then
        echo -e "${YELLOW}⚠ No Kafka Connect pod found for DNS testing${NC}"
        return 1
    fi
    
    local services=("postgresql.data-ingestion.svc.cluster.local" "kafka-headless.data-ingestion.svc.cluster.local" "schema-registry.data-ingestion.svc.cluster.local")
    
    for service in "${services[@]}"; do
        echo -n "  - $service: "
        if kubectl exec -n "$ns" "$test_pod" -- nslookup "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ RESOLVES${NC}"
        else
            echo -e "${RED}✗ FAILS${NC}"
        fi
    done
}

# Function to check for default deny policies
check_default_deny() {
    local ns=$1
    
    echo "Checking for default deny policies:"
    
    # Check if there's a default deny-all policy
    echo -n "  - Default deny-all ingress: "
    if kubectl get networkpolicy -n "$ns" -o yaml | grep -q "podSelector: {}"; then
        echo -e "${GREEN}✓ CONFIGURED${NC}"
    else
        echo -e "${YELLOW}⚠ NOT CONFIGURED${NC}"
        echo "    Recommendation: Implement default deny-all policy for better security"
    fi
}

# Function to generate network security recommendations
generate_network_recommendations() {
    echo
    echo "=== Network Security Recommendations ==="
    echo
    echo "1. Default Deny Policy:"
    echo "   - Implement a default deny-all NetworkPolicy"
    echo "   - Explicitly allow only required connections"
    echo
    echo "2. Component-Specific Policies:"
    echo "   - PostgreSQL: Allow ingress only from Kafka Connect"
    echo "   - Kafka: Allow ingress from Kafka Connect and Schema Registry"
    echo "   - Schema Registry: Allow ingress from Kafka Connect"
    echo "   - Kafka Connect: Allow egress to PostgreSQL, Kafka, Schema Registry, and S3"
    echo
    echo "3. DNS and System Services:"
    echo "   - Allow DNS resolution to kube-system/kube-dns"
    echo "   - Allow access to Kubernetes API if needed"
    echo
    echo "4. External Access:"
    echo "   - Restrict egress to specific external services (S3 endpoints)"
    echo "   - Use FQDN-based policies where supported"
    echo
    echo "5. Monitoring and Logging:"
    echo "   - Allow access to monitoring systems (Prometheus, Grafana)"
    echo "   - Ensure logging infrastructure can collect logs"
}

# Function to create test network policy (dry-run)
create_test_policy() {
    local ns=$1
    
    echo "Example NetworkPolicy for data pipeline security:"
    
    cat << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: data-pipeline-security
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []  # Deny all ingress by default
  egress:
  # Allow DNS resolution
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow access to Kubernetes API
  - to: []
    ports:
    - protocol: TCP
      port: 443
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kafka-connect-policy
  namespace: $ns
spec:
  podSelector:
    matchLabels:
      app: kafka-connect
  policyTypes:
  - Egress
  egress:
  # Allow access to PostgreSQL
  - to:
    - podSelector:
        matchLabels:
          app: postgresql
    ports:
    - protocol: TCP
      port: 5432
  # Allow access to Kafka
  - to:
    - podSelector:
        matchLabels:
          app: kafka
    ports:
    - protocol: TCP
      port: 9092
  # Allow access to Schema Registry
  - to:
    - podSelector:
        matchLabels:
          app: schema-registry
    ports:
    - protocol: TCP
      port: 8081
  # Allow external access for S3
  - to: []
    ports:
    - protocol: TCP
      port: 443
EOF
}

# Main validation
main() {
    local exit_code=0
    
    echo "Starting network policy validation..."
    echo
    
    # Check namespace exists
    if ! check_namespace "$NAMESPACE"; then
        echo -e "${RED}ERROR: Namespace does not exist${NC}"
        exit 1
    fi
    
    echo
    
    # List network policies
    if ! list_network_policies "$NAMESPACE"; then
        exit_code=1
    fi
    
    echo
    
    # Analyze each network policy
    local policies=$(kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$policies" ]; then
        for policy in $policies; do
            analyze_network_policy "$NAMESPACE" "$policy"
            echo
        done
    fi
    
    # Test network connectivity
    test_network_connectivity "$NAMESPACE"
    
    echo
    
    # Test DNS resolution
    test_dns_resolution "$NAMESPACE"
    
    echo
    
    # Check for default deny policies
    check_default_deny "$NAMESPACE"
    
    # Generate recommendations
    generate_network_recommendations
    
    echo
    echo "=== Example NetworkPolicy ==="
    create_test_policy "$NAMESPACE"
    
    # Generate audit report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file="/tmp/network-policy-audit-$timestamp.json"
    
    cat > "$report_file" << EOF
{
  "audit_type": "network_policy",
  "timestamp": "$timestamp",
  "namespace": "$NAMESPACE",
  "status": $([ $exit_code -eq 0 ] && echo '"PASS"' || echo '"FAIL"'),
  "checks_performed": [
    "network_policies_exist",
    "connectivity_testing",
    "dns_resolution",
    "default_deny_check"
  ],
  "policies_found": [$(kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{range .items[*]}"{.metadata.name}"{end}' 2>/dev/null | sed 's/""/, /g' | sed 's/, $//' || echo "")]
}
EOF
    
    echo
    echo "=== Validation Summary ==="
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Network policy validation completed${NC}"
    else
        echo -e "${YELLOW}⚠ Network policy validation completed with warnings${NC}"
    fi
    echo "Audit report saved to: $report_file"
    
    exit $exit_code
}

# Run main function
main "$@"