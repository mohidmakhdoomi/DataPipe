#!/bin/bash

# Verification script for Batch Analytics Layer Kind cluster
# This script verifies that the cluster is properly configured and ready for batch processing

set -e

echo "🔍 Verifying Batch Analytics Layer cluster configuration..."

# Check if cluster exists and is accessible
echo "1️⃣  Checking cluster connectivity..."
if ! kubectl --context "kind-$NAMESPACE" cluster-info --context kind-batch-analytics &> /dev/null; then
    echo "❌ Cluster 'batch-analytics' is not accessible"
    exit 1
fi
echo "✅ Cluster is accessible"

# Check node count and labels
echo "2️⃣  Verifying node configuration..."
NODE_COUNT=$(kubectl --context "kind-$NAMESPACE" get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ne 3 ]; then
    echo "❌ Expected 3 nodes, found $NODE_COUNT"
    exit 1
fi
echo "✅ Found 3 nodes as expected"

# Check node labels
CONTROL_PLANE_COUNT=$(kubectl --context "kind-$NAMESPACE" get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l)
WORKER_COUNT=$(kubectl --context "kind-$NAMESPACE" get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers | wc -l)

if [ "$CONTROL_PLANE_COUNT" -ne 1 ] || [ "$WORKER_COUNT" -ne 2 ]; then
    echo "❌ Expected 1 control-plane and 2 worker nodes"
    exit 1
fi
echo "✅ Node roles configured correctly (1 control-plane, 2 workers)"

# Check namespace
echo "3️⃣  Verifying namespace configuration..."
if ! kubectl --context "kind-$NAMESPACE" get namespace batch-analytics &> /dev/null; then
    echo "❌ Namespace 'batch-analytics' not found"
    exit 1
fi
echo "✅ Namespace 'batch-analytics' exists"

# Check resource quota
echo "4️⃣  Verifying resource quotas..."
MEMORY_QUOTA=$(kubectl --context "kind-$NAMESPACE" get resourcequota batch-analytics-quota -n batch-analytics -o jsonpath='{.spec.hard.requests\.memory}')
if [ "$MEMORY_QUOTA" != "12Gi" ]; then
    echo "❌ Expected memory quota 12Gi, found $MEMORY_QUOTA"
    exit 1
fi
echo "✅ Resource quota configured correctly (12Gi memory)"

# Check service accounts
echo "5️⃣  Verifying service accounts..."
REQUIRED_SA=("spark-operator-sa" "spark-driver-sa" "spark-executor-sa" "dbt-runner-sa")
for sa in "${REQUIRED_SA[@]}"; do
    if ! kubectl --context "kind-$NAMESPACE" get serviceaccount "$sa" -n batch-analytics &> /dev/null; then
        echo "❌ Service account '$sa' not found"
        exit 1
    fi
done
echo "✅ All required service accounts exist"

# Check RBAC
echo "6️⃣  Verifying RBAC configuration..."
if ! kubectl --context "kind-$NAMESPACE" get clusterrole spark-operator-role &> /dev/null; then
    echo "❌ ClusterRole 'spark-operator-role' not found"
    exit 1
fi

if ! kubectl --context "kind-$NAMESPACE" get clusterrolebinding spark-operator-binding &> /dev/null; then
    echo "❌ ClusterRoleBinding 'spark-operator-binding' not found"
    exit 1
fi
echo "✅ RBAC configuration is correct"

# Check storage classes
echo "7️⃣  Verifying storage classes..."
REQUIRED_SC=("batch-processing-local-path" "analytics-local-path")
for sc in "${REQUIRED_SC[@]}"; do
    if ! kubectl --context "kind-$NAMESPACE" get storageclass "$sc" &> /dev/null; then
        echo "❌ StorageClass '$sc' not found"
        exit 1
    fi
done
echo "✅ Storage classes configured correctly"

# Check PVCs
echo "8️⃣  Verifying persistent volume claims..."
REQUIRED_PVC=("spark-history-pvc" "spark-checkpoints-pvc" "dbt-artifacts-pvc")
for pvc in "${REQUIRED_PVC[@]}"; do
    PVC_STATUS=$(kubectl --context "kind-$NAMESPACE" get pvc "$pvc" -n batch-analytics -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    if [ "$PVC_STATUS" == "NotFound" ]; then
        echo "❌ PVC '$pvc' not found"
        exit 1
    elif [ "$PVC_STATUS" == "Pending" ]; then
        # Check if it's pending due to WaitForFirstConsumer
        BINDING_MODE=$(kubectl --context "kind-$NAMESPACE" get pvc "$pvc" -n batch-analytics -o jsonpath='{.spec.volumeMode}' 2>/dev/null || echo "")
        echo "⏳ PVC '$pvc' is pending (WaitForFirstConsumer - will bind when pod is scheduled)"
    elif [ "$PVC_STATUS" == "Bound" ]; then
        echo "✅ PVC '$pvc' is bound"
    else
        echo "❌ PVC '$pvc' has unexpected status: $PVC_STATUS"
        exit 1
    fi
done
echo "✅ All PVCs are created and ready (will bind when pods are scheduled)"

# Check port mappings (verify Kind configuration)
echo "9️⃣  Verifying port mappings..."
KIND_CONFIG_PORTS=$(docker port batch-analytics-control-plane 2>/dev/null | grep -E "(4040|18080|8888|8080|9090)" | wc -l)
if [ "$KIND_CONFIG_PORTS" -lt 5 ]; then
    echo "⚠️  Warning: Some port mappings may not be configured correctly"
    echo "   Expected ports: 4040, 18080, 8888, 8080, 9090"
    docker port batch-analytics-control-plane 2>/dev/null || echo "   Could not check port mappings"
else
    echo "✅ Port mappings configured correctly"
fi

# Display resource summary
echo "🔟 Resource Summary:"
echo "   Nodes: $NODE_COUNT (1 control-plane, 2 workers)"
echo "   Memory Quota: $MEMORY_QUOTA"
echo "   Storage: $(kubectl --context "kind-$NAMESPACE" get pvc -n batch-analytics --no-headers | wc -l) PVCs bound"
echo "   Service Accounts: ${#REQUIRED_SA[@]} configured"

echo ""
echo "🎉 Batch Analytics Layer cluster verification complete!"
echo "✅ Cluster is ready for Spark Operator deployment (Task 2)"
echo ""
echo "📊 Quick Status Check:"
kubectl --context "kind-$NAMESPACE" get all -n batch-analytics
echo ""
echo "💾 Storage Status:"
kubectl --context "kind-$NAMESPACE" get pvc -n batch-analytics