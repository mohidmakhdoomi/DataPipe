#!/bin/bash
# PostgreSQL Point-in-Time Recovery Script
# Restores database to a specific point in time
# Usage: ./postgresql-pitr-restore.sh <backup_path> <target_time>

set -e

BACKUP_PATH=$1
TARGET_TIME=$2
NAMESPACE="data-ingestion"
POD_NAME="postgresql-0"

if [ -z "$BACKUP_PATH" ] || [ -z "$TARGET_TIME" ]; then
  echo "Usage: $0 <backup_path> <target_time>"
  echo "Example: $0 /e/Projects/DataPipe/backups/postgresql/base/20250106_020000 '2025-01-06 14:30:00'"
  exit 1
fi

if [ ! -f "${BACKUP_PATH}/base.tar.gz" ]; then
  echo "ERROR: Backup file not found: ${BACKUP_PATH}/base.tar.gz"
  exit 1
fi

echo "=== PostgreSQL Point-in-Time Recovery ==="
echo "Backup Path: ${BACKUP_PATH}"
echo "Target Time: ${TARGET_TIME}"
echo ""
read -p "This will STOP and RESTORE PostgreSQL. Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Aborted"
  exit 0
fi

# Stop PostgreSQL
echo "Stopping PostgreSQL..."
kubectl scale statefulset postgresql -n ${NAMESPACE} --replicas=0

# Wait for pod to terminate
echo "Waiting for pod to terminate..."
kubectl wait --for=delete pod/${POD_NAME} -n ${NAMESPACE} --timeout=60s || true

# Start PostgreSQL pod in maintenance mode
echo "Starting PostgreSQL in maintenance mode..."
kubectl scale statefulset postgresql -n ${NAMESPACE} --replicas=1
kubectl wait --for=condition=ready pod/${POD_NAME} -n ${NAMESPACE} --timeout=120s

# Stop PostgreSQL service inside pod
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- su - postgres -c "pg_ctl stop -D /var/lib/postgresql/data/pgdata -m fast" || true
sleep 5

# Clear data directory
echo "Clearing data directory..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm -rf /var/lib/postgresql/data/pgdata/*

# Copy and extract base backup
echo "Restoring base backup..."
kubectl cp "${BACKUP_PATH}/base.tar.gz" ${NAMESPACE}/${POD_NAME}:/tmp/base.tar.gz
kubectl cp "${BACKUP_PATH}/pg_wal.tar.gz" ${NAMESPACE}/${POD_NAME}:/tmp/pg_wal.tar.gz

kubectl exec -n ${NAMESPACE} ${POD_NAME} -- bash -c "
  cd /var/lib/postgresql/data/pgdata
  tar -xzf /tmp/base.tar.gz
  mkdir -p pg_wal
  cd pg_wal
  tar -xzf /tmp/pg_wal.tar.gz
  cd ..
  chown -R postgres:postgres /var/lib/postgresql/data/pgdata
"

# Create recovery signal file (PostgreSQL 12+)
echo "Creating recovery configuration..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- bash -c "
  cat > /var/lib/postgresql/data/pgdata/recovery.signal <<EOF
# Recovery signal file
EOF

  cat >> /var/lib/postgresql/data/pgdata/postgresql.auto.conf <<EOF
restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
recovery_target_time = '${TARGET_TIME}'
recovery_target_action = 'promote'
EOF

  chown postgres:postgres /var/lib/postgresql/data/pgdata/recovery.signal
  chown postgres:postgres /var/lib/postgresql/data/pgdata/postgresql.auto.conf
"

# Cleanup temporary files
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm -f /tmp/base.tar.gz /tmp/pg_wal.tar.gz

# Restart PostgreSQL to begin recovery
echo "Starting PostgreSQL recovery process..."
kubectl delete pod ${POD_NAME} -n ${NAMESPACE}
kubectl wait --for=condition=ready pod/${POD_NAME} -n ${NAMESPACE} --timeout=300s

# Wait for recovery to complete
echo "Waiting for recovery to complete..."
sleep 10

# Check recovery status
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c "SELECT pg_is_in_recovery();"

echo ""
echo "=== PITR Restore Complete ==="
echo "Database restored to: ${TARGET_TIME}"
echo "Please verify data integrity before resuming CDC connectors"
