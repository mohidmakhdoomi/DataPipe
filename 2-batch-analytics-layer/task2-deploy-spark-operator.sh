#!/bin/bash

# Task 2: Deploy Spark Operator for Batch Analytics Layer
# Installs Spark Operator via Helm with resource constraints and existing service accounts

set -e

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Task 2: Deploy Spark Operator for Batch Analytics Layer ==="
echo "Timestamp: $(date)"
echo

# Check if kind cluster is running
echo "1. Verifying batch-analytics cluster is running..."
if ! kind get clusters | grep -q "batch-analytics"; then
    echo "ERROR: batch-analytics cluster not found. Please run Task 1 first."
    exit 1
fi

# Set kubectl context
kubectl config use-context kind-batch-analytics

# Verify namespace and service accounts exist
echo "2. Verifying prerequisites from Task 1..."
if ! kubectl get namespace batch-analytics >/dev/null 2>&1; then
    echo "ERROR: batch-analytics namespace not found. Please run Task 1 first."
    exit 1
fi

if ! kubectl get serviceaccount spark-operator-sa -n batch-analytics >/dev/null 2>&1; then
    echo "ERROR: spark-operator-sa service account not found. Please run Task 1 first."
    exit 1
fi

echo "✓ Prerequisites verified"
echo

# Add Spark Operator Helm repository
echo "3. Adding Spark Operator Helm repository..."
helm repo add --force-update spark-operator https://kubeflow.github.io/spark-operator
helm repo update
echo "✓ Helm repository added"
echo

# Install Spark Operator
echo "4. Installing Spark Operator with resource constraints..."
helm install batch-analytics spark-operator/spark-operator \
  --namespace batch-analytics \
  --values task2-spark-operator-values.yaml \
  --wait \
  --timeout 300s


if [ $? -eq 0 ]; then
    echo "✓ Spark Operator installed successfully"
else
    echo "ERROR: Failed to install Spark Operator"
    exit 1
fi
echo

# Deploy Spark History Server
echo "5. Deploying Spark History Server..."
kubectl apply -f task2-spark-history-server.yaml

# Wait for History Server to be ready
echo "6. Waiting for Spark History Server to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/spark-history-server -n batch-analytics

if [ $? -eq 0 ]; then
    echo "✓ Spark History Server deployed and ready"
else
    echo "ERROR: Spark History Server failed to become ready"
    exit 1
fi
echo

# Verify Spark Operator is running
echo "7. Verifying Spark Operator deployment..."
kubectl get pods -n batch-analytics | grep spark-history
echo

# # Apply CustomResourceDefinitions
# echo "8. Apply CustomResourceDefinitions..."
# kubectl apply -k crds/

# Test basic SparkApplication submission
echo "9. Testing basic SparkApplication submission..."
kubectl apply -f task2-spark-test-job.yaml

echo "✓ Test SparkApplication submitted"
echo

# Display access information
echo "=== Task 2 Deployment Complete ==="
echo
echo "Spark Operator Status:"
kubectl get pods -n batch-analytics | grep spark-operator
echo
echo "History Server Status:"
kubectl get pods -n batch-analytics | grep spark-history
echo
echo "Access Information:"
echo "- Spark History Server: http://localhost:18080 (via port-forward or kind port mapping)"
echo "- Port forward command: kubectl port-forward svc/spark-history-server -n batch-analytics 18080:18080"
echo
echo "Monitor test job:"
echo "- kubectl get sparkapplication -n batch-analytics -w"
echo "- kubectl get pods -n batch-analytics -w"
echo
echo "Next Steps:"
echo "- Task 3: Configure AWS S3 access and credentials"
echo "- Task 4: Set up Snowflake connection and authentication"
echo

echo "Task 2 completed successfully at $(date)"