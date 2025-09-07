#!/bin/bash
# validate-rbac.sh
# Validates RBAC configuration for data ingestion pipeline

set -e

NAMESPACE="data-ingestion"

echo "=== RBAC Validation for Data Ingestion Pipeline ==="
echo "Namespace: $NAMESPACE"
echo "Date: $(date)"
echo ""

# Check service account token mounting (should be disabled)
echo "=== Service Account Token Mounting Validation ==="
for sa in postgresql-sa kafka-sa debezium-sa schema-registry-sa kafka-connect-sa; do
    echo -n "Checking $sa token mounting: "
    TOKEN_MOUNT=$(kubectl get serviceaccount $sa -n $NAMESPACE -o jsonpath='{.automountServiceAccountToken}')
    if [ "$TOKEN_MOUNT" = "false" ]; then
        echo "✓ SECURE (disabled)"
    else
        echo "✗ INSECURE (enabled or not set)"
    fi
done
echo ""

# Validate kafka-connect-sa permissions (should have these)
echo "=== Kafka Connect Service Account Required Permissions ==="
echo -n "Can get configmaps: "
if kubectl auth can-i get configmaps --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

echo -n "Can get secrets: "
if kubectl auth can-i get secrets --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

echo -n "Can get pods: "
if kubectl auth can-i get pods --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

echo -n "Can list configmaps: "
if kubectl auth can-i list configmaps --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

echo -n "Can watch configmaps: "
if kubectl auth can-i watch configmaps --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi
echo ""

# Validate restricted permissions (should NOT have these)
echo "=== Kafka Connect Service Account Restricted Permissions ==="
echo -n "Can create pods: "
if kubectl auth can-i create pods --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✗ YES (SHOULD BE NO)"
else
    echo "✓ NO"
fi

echo -n "Can delete secrets: "
if kubectl auth can-i delete secrets --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✗ YES (SHOULD BE NO)"
else
    echo "✓ NO"
fi

echo -n "Can update secrets: "
if kubectl auth can-i update secrets --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n $NAMESPACE --quiet; then
    echo "✗ YES (SHOULD BE NO)"
else
    echo "✓ NO"
fi

echo -n "Can access kube-system secrets: "
if kubectl auth can-i get secrets --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n kube-system --quiet; then
    echo "✗ YES (SHOULD BE NO)"
else
    echo "✓ NO"
fi

echo -n "Can access default namespace: "
if kubectl auth can-i get pods --as=system:serviceaccount:$NAMESPACE:kafka-connect-sa -n default --quiet; then
    echo "✗ YES (SHOULD BE NO)"
else
    echo "✓ NO"
fi
echo ""

# Check other service accounts (should have minimal permissions)
echo "=== Other Service Account Permissions (Should be minimal) ==="
for sa in postgresql-sa kafka-sa debezium-sa schema-registry-sa; do
    echo "Checking $sa permissions:"
    echo -n "  Can get pods: "
    if kubectl auth can-i get pods --as=system:serviceaccount:$NAMESPACE:$sa -n $NAMESPACE --quiet; then
        echo "✗ YES (SHOULD BE NO)"
    else
        echo "✓ NO"
    fi
    
    echo -n "  Can get secrets: "
    if kubectl auth can-i get secrets --as=system:serviceaccount:$NAMESPACE:$sa -n $NAMESPACE --quiet; then
        echo "✗ YES (SHOULD BE NO)"
    else
        echo "✓ NO"
    fi
done
echo ""

# Validate Role and RoleBinding
echo "=== Role and RoleBinding Validation ==="
echo -n "kafka-connect-role exists: "
if kubectl get role kafka-connect-role -n $NAMESPACE >/dev/null 2>&1; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

echo -n "kafka-connect-rolebinding exists: "
if kubectl get rolebinding kafka-connect-rolebinding -n $NAMESPACE >/dev/null 2>&1; then
    echo "✓ YES"
else
    echo "✗ NO (REQUIRED)"
fi

# Check role permissions
echo ""
echo "=== Role Permissions Details ==="
kubectl describe role kafka-connect-role -n $NAMESPACE 2>/dev/null || echo "Role not found"

echo ""
echo "=== RoleBinding Details ==="
kubectl describe rolebinding kafka-connect-rolebinding -n $NAMESPACE 2>/dev/null || echo "RoleBinding not found"

echo ""
echo "=== RBAC Validation Complete ==="