#!/bin/bash
# validate-network-policies.sh
# Validates network policy configuration for data ingestion pipeline

set -e

NAMESPACE="data-ingestion"

echo "=== Network Policy Validation for Data Ingestion Pipeline ==="
echo "Namespace: $NAMESPACE"
echo "Date: $(date)"
echo ""

# Check if network policies exist
echo "=== Network Policy Existence Check ==="
POLICIES=("default-deny-all" "allow-dns" "postgresql-netpol" "kafka-netpol" "kafka-connect-netpol" "schema-registry-netpol")

for policy in "${POLICIES[@]}"; do
    echo -n "Checking $policy: "
    if kubectl get networkpolicy $policy -n $NAMESPACE >/dev/null 2>&1; then
        echo "✓ EXISTS"
    else
        echo "✗ MISSING"
    fi
done
echo ""

# Test PostgreSQL access restrictions
echo "=== PostgreSQL Network Access Validation ==="
echo "Testing PostgreSQL access from authorized pod (kafka-connect)..."

# Create a test pod with kafka-connect labels
kubectl run test-kafka-connect --image=postgres:13 --rm -i --restart=Never -n $NAMESPACE \
  --labels="app=kafka-connect" \
  --command -- timeout 10 psql -h postgresql.data-ingestion.svc.cluster.local -U postgres -d ecommerce -c "SELECT 1;" 2>/dev/null && \
  echo "✓ Authorized access works" || echo "✗ Authorized access failed"

echo "Testing PostgreSQL access from unauthorized pod..."
# Create a test pod without proper labels
kubectl run test-unauthorized --image=postgres:13 --rm -i --restart=Never -n $NAMESPACE \
  --command -- timeout 5 psql -h postgresql.data-ingestion.svc.cluster.local -U postgres -d ecommerce -c "SELECT 1;" 2>/dev/null && \
  echo "✗ Unauthorized access succeeded (SECURITY ISSUE)" || echo "✓ Unauthorized access blocked"

echo ""

# Test Kafka access restrictions
echo "=== Kafka Network Access Validation ==="
echo "Testing Kafka access from authorized pod (kafka-connect)..."
kubectl run test-kafka-connect-kafka --image=confluentinc/cp-kafka:7.4.0 --rm -i --restart=Never -n $NAMESPACE \
  --labels="app=kafka-connect" \
  --command -- timeout 10 kafka-topics --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 --list 2>/dev/null && \
  echo "✓ Authorized Kafka access works" || echo "✗ Authorized Kafka access failed"

echo "Testing Kafka access from unauthorized pod..."
kubectl run test-unauthorized-kafka --image=confluentinc/cp-kafka:7.4.0 --rm -i --restart=Never -n $NAMESPACE \
  --command -- timeout 5 kafka-topics --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 --list 2>/dev/null && \
  echo "✗ Unauthorized Kafka access succeeded (SECURITY ISSUE)" || echo "✓ Unauthorized Kafka access blocked"

echo ""

# Test Schema Registry access restrictions
echo "=== Schema Registry Network Access Validation ==="
echo "Testing Schema Registry access from authorized pod (kafka-connect)..."
kubectl run test-kafka-connect-sr --image=curlimages/curl --rm -i --restart=Never -n $NAMESPACE \
  --labels="app=kafka-connect" \
  --command -- timeout 10 curl -f http://schema-registry.data-ingestion.svc.cluster.local:8081/subjects 2>/dev/null && \
  echo "✓ Authorized Schema Registry access works" || echo "✗ Authorized Schema Registry access failed"

echo "Testing Schema Registry access from unauthorized pod..."
kubectl run test-unauthorized-sr --image=curlimages/curl --rm -i --restart=Never -n $NAMESPACE \
  --command -- timeout 5 curl -f http://schema-registry.data-ingestion.svc.cluster.local:8081/subjects 2>/dev/null && \
  echo "✗ Unauthorized Schema Registry access succeeded (SECURITY ISSUE)" || echo "✓ Unauthorized Schema Registry access blocked"

echo ""

# Test cross-namespace access (should be blocked)
echo "=== Cross-Namespace Access Validation ==="
echo "Testing PostgreSQL access from default namespace (should be blocked)..."
kubectl run test-cross-ns-pg --image=postgres:13 --rm -i --restart=Never -n default \
  --command -- timeout 5 psql -h postgresql.data-ingestion.svc.cluster.local -U postgres -d ecommerce -c "SELECT 1;" 2>/dev/null && \
  echo "✗ Cross-namespace PostgreSQL access succeeded (SECURITY ISSUE)" || echo "✓ Cross-namespace PostgreSQL access blocked"

echo "Testing Kafka access from default namespace (should be blocked)..."
kubectl run test-cross-ns-kafka --image=confluentinc/cp-kafka:7.4.0 --rm -i --restart=Never -n default \
  --command -- timeout 5 kafka-topics --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 --list 2>/dev/null && \
  echo "✗ Cross-namespace Kafka access succeeded (SECURITY ISSUE)" || echo "✓ Cross-namespace Kafka access blocked"

echo ""

# Test DNS resolution (should work for all pods)
echo "=== DNS Resolution Validation ==="
echo "Testing DNS resolution from data-ingestion namespace..."
kubectl run test-dns --image=curlimages/curl --rm -i --restart=Never -n $NAMESPACE \
  --command -- timeout 5 nslookup kubernetes.default.svc.cluster.local 2>/dev/null && \
  echo "✓ DNS resolution works" || echo "✗ DNS resolution failed"

echo ""

# Test external connectivity (should work for kafka-connect to S3)
echo "=== External Connectivity Validation ==="
echo "Testing HTTPS connectivity from kafka-connect pod..."
kubectl run test-external --image=curlimages/curl --rm -i --restart=Never -n $NAMESPACE \
  --labels="app=kafka-connect" \
  --command -- timeout 10 curl -f https://s3.amazonaws.com 2>/dev/null && \
  echo "✓ External HTTPS access works" || echo "✗ External HTTPS access failed"

echo "Testing HTTP connectivity (should be blocked)..."
kubectl run test-http --image=curlimages/curl --rm -i --restart=Never -n $NAMESPACE \
  --labels="app=kafka-connect" \
  --command -- timeout 5 curl -f http://httpbin.org/get 2>/dev/null && \
  echo "✗ HTTP access succeeded (SHOULD BE BLOCKED)" || echo "✓ HTTP access blocked"

echo ""

# Validate network policy configuration details
echo "=== Network Policy Configuration Details ==="
echo "Default deny all policy:"
kubectl get networkpolicy default-deny-all -n $NAMESPACE -o yaml | grep -A 10 "spec:" || echo "Policy not found"

echo ""
echo "PostgreSQL network policy ingress rules:"
kubectl get networkpolicy postgresql-netpol -n $NAMESPACE -o jsonpath='{.spec.ingress}' | jq '.' 2>/dev/null || echo "Policy not found or invalid JSON"

echo ""
echo "Kafka Connect network policy egress rules:"
kubectl get networkpolicy kafka-connect-netpol -n $NAMESPACE -o jsonpath='{.spec.egress}' | jq '.' 2>/dev/null || echo "Policy not found or invalid JSON"

echo ""
echo "=== Network Policy Validation Complete ==="