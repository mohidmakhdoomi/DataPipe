#!/bin/bash

# Setup script for Batch Analytics Layer Kind cluster
# This script creates and configures the Kind cluster for batch processing

set -e

readonly NAMESPACE="batch-analytics"

echo "🚀 Setting up Batch Analytics Layer Kind cluster..."

# Check if Kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ Kind is not installed. Please install Kind first."
    echo "   Visit: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Delete existing cluster if it exists
echo "🧹 Cleaning up existing cluster (if any)..."
kind delete cluster --name "$NAMESPACE" 2>/dev/null || true

# Create the Kind cluster
echo "🏗️  Creating Kind cluster for batch analytics..."
kind create cluster --config batch-kind-config.yaml --wait 300s

# Verify cluster is ready
echo "🔍 Verifying cluster status..."
kubectl cluster-info --context "kind-$NAMESPACE"

# Check node status and resources
echo "📊 Checking node status and resources..."
kubectl --context "kind-$NAMESPACE" get nodes -o wide
kubectl --context "kind-$NAMESPACE" describe nodes | grep -E "(Name:|Allocatable:|cpu:|memory:)"

# Apply namespace and RBAC
echo "🔐 Setting up namespace and RBAC..."
kubectl --context "kind-$NAMESPACE" apply -f batch-01-namespace.yaml
kubectl --context "kind-$NAMESPACE" apply -f batch-02-service-accounts.yaml

# Apply storage classes and PVCs
echo "💾 Setting up storage..."
kubectl --context "kind-$NAMESPACE" apply -f batch-storage-classes.yaml
kubectl --context "kind-$NAMESPACE" apply -f batch-pvcs.yaml

# Wait for PVCs to be bound
echo "⏳ Waiting for PVCs to be ready..."
kubectl --context "kind-$NAMESPACE" wait --for=condition=Bound pvc/spark-history-pvc -n "$NAMESPACE" --timeout=60s
kubectl --context "kind-$NAMESPACE" wait --for=condition=Bound pvc/spark-checkpoints-pvc -n "$NAMESPACE" --timeout=60s
kubectl --context "kind-$NAMESPACE" wait --for=condition=Bound pvc/dbt-artifacts-pvc -n "$NAMESPACE" --timeout=60s

# Verify resource quotas
echo "📋 Verifying resource quotas..."
kubectl --context "kind-$NAMESPACE" get resourcequota -n "$NAMESPACE"
kubectl --context "kind-$NAMESPACE" describe resourcequota batch-analytics-quota -n "$NAMESPACE"

# Check storage classes and PVCs
echo "💿 Checking storage configuration..."
kubectl --context "kind-$NAMESPACE" get storageclass
kubectl --context "kind-$NAMESPACE" get pvc -n "$NAMESPACE"

# Display cluster information
echo ""
echo "✅ Batch Analytics Layer cluster setup complete!"
echo ""
echo "📊 Cluster Information:"
echo "  Cluster Name: $NAMESPACE"
echo "  Namespace: $NAMESPACE"
echo "  Resource Allocation: 12Gi RAM, 6-8 CPU"
echo ""
echo "🔗 Port Mappings:"
echo "  Spark UI: http://localhost:4040"
echo "  Spark History: http://localhost:18080"
echo "  Jupyter: http://localhost:8888"
echo "  dbt Docs: http://localhost:8080"
echo "  Monitoring: http://localhost:9090"
echo ""
echo "🎯 Next Steps:"
echo "  1. Deploy Spark Operator (Task 2)"
echo "  2. Configure AWS S3 access (Task 3)"
echo "  3. Set up Snowflake connection (Task 4)"
echo ""
echo "🔧 Useful Commands:"
echo "  kubectl --context \"kind-$NAMESPACE\" get all -n \"$NAMESPACE\""
echo "  kubectl --context \"kind-$NAMESPACE\" logs -n \"$NAMESPACE\" <pod-name>"
echo "  kind delete cluster --name $NAMESPACE"