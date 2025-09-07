#!/bin/bash
# rotate-postgresql-credentials.sh
# Rotates PostgreSQL CDC user credentials

set -e

NAMESPACE="data-ingestion"
SECRET_NAME="debezium-credentials"
DB_USER="debezium"

echo "=== PostgreSQL CDC Credential Rotation ==="
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"
echo "Database User: $DB_USER"

# Generate new secure password
NEW_PASSWORD=$(openssl rand -base64 32)
echo "Generated new password for user: $DB_USER"

# Get PostgreSQL pod name
PG_POD=$(kubectl get pods -n $NAMESPACE -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
if [ -z "$PG_POD" ]; then
    echo "ERROR: PostgreSQL pod not found"
    exit 1
fi

echo "PostgreSQL pod: $PG_POD"

# Update PostgreSQL user password
echo "Updating PostgreSQL user password..."
kubectl exec -n $NAMESPACE $PG_POD -- psql -U postgres -d ecommerce -c "ALTER USER $DB_USER WITH PASSWORD '$NEW_PASSWORD';"

# Verify user permissions
echo "Verifying user permissions..."
kubectl exec -n $NAMESPACE $PG_POD -- psql -U postgres -d ecommerce -c "SELECT usename, userepl, usesuper FROM pg_user WHERE usename = '$DB_USER';"

# Encode new password for Kubernetes secret
NEW_PASSWORD_B64=$(echo -n "$NEW_PASSWORD" | base64 -w 0)

# Update Kubernetes secret
echo "Updating Kubernetes secret..."
kubectl patch secret $SECRET_NAME -n $NAMESPACE \
  --type='json' \
  -p="[{'op': 'replace', 'path': '/data/db-password', 'value': '$NEW_PASSWORD_B64'}]"

# Restart Kafka Connect to pick up new credentials
echo "Restarting Kafka Connect..."
kubectl rollout restart deployment kafka-connect -n $NAMESPACE

# Wait for rollout to complete
echo "Waiting for Kafka Connect rollout to complete..."
kubectl rollout status deployment kafka-connect -n $NAMESPACE --timeout=300s

# Wait a bit for connector to stabilize
echo "Waiting for connector to stabilize..."
sleep 30

# Verify CDC connector status
echo "Verifying CDC connector status..."
CONNECT_POD=$(kubectl get pods -n $NAMESPACE -l app=kafka-connect -o jsonpath='{.items[0].metadata.name}')
if [ -n "$CONNECT_POD" ]; then
    kubectl exec -n $NAMESPACE $CONNECT_POD -- \
      curl -s http://localhost:8083/connectors/postgres-cdc-connector/status | jq '.connector.state'
else
    echo "WARNING: Kafka Connect pod not found for verification"
fi

echo "=== PostgreSQL credential rotation completed successfully ==="
echo "New password has been set and Kafka Connect has been restarted"
echo "Please monitor the CDC connector for proper operation"