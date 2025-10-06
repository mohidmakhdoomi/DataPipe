#!/bin/bash
# PostgreSQL Base Backup Script
# Performs full physical backup using pg_basebackup
# Usage: ./postgresql-base-backup.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-/e/Projects/DataPipe/backups/postgresql/base}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
NAMESPACE="data-ingestion"
POD_NAME="postgresql-0"

echo "=== PostgreSQL Base Backup ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Backup Path: ${BACKUP_PATH}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Check if PostgreSQL pod is running
if ! kubectl get pod -n ${NAMESPACE} ${POD_NAME} &> /dev/null; then
  echo "ERROR: PostgreSQL pod not found"
  exit 1
fi

# Perform base backup inside the pod
echo "Starting base backup..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- bash -c "
  mkdir -p /tmp/backup
  pg_basebackup -D /tmp/backup -F tar -z -P -U postgres -w
  echo 'Base backup completed in pod'
"

# Copy backup from pod to local storage
echo "Copying backup from pod..."
kubectl cp ${NAMESPACE}/${POD_NAME}:/tmp/backup/base.tar.gz "${BACKUP_PATH}/base.tar.gz"
kubectl cp ${NAMESPACE}/${POD_NAME}:/tmp/backup/pg_wal.tar.gz "${BACKUP_PATH}/pg_wal.tar.gz"

# Cleanup temporary files in pod
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm -rf /tmp/backup

# Verify backup integrity
echo "Verifying backup integrity..."
if tar -tzf "${BACKUP_PATH}/base.tar.gz" > /dev/null 2>&1; then
  echo "✅ Backup verification successful"
  
  # Create backup metadata
  cat > "${BACKUP_PATH}/backup_info.txt" <<EOF
Backup Type: Base Backup
Timestamp: ${TIMESTAMP}
Database: ecommerce
Size: $(du -sh "${BACKUP_PATH}" | cut -f1)
Status: SUCCESS
EOF
  
  echo "Backup completed successfully: ${BACKUP_PATH}"
else
  echo "❌ ERROR: Backup verification failed"
  exit 1
fi

# Cleanup old backups (keep last 7 days)
echo "Cleaning up old backups..."
find "${BACKUP_DIR}" -type d -name "20*" -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "=== Backup Complete ==="
