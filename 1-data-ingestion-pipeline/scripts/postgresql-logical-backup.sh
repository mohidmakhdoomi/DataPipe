#!/bin/bash
# PostgreSQL Logical Backup Script
# Performs logical backup using pg_dump for schema and data
# Usage: ./postgresql-logical-backup.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-/e/Projects/DataPipe/backups/postgresql/logical}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAMESPACE="data-ingestion"
POD_NAME="postgresql-0"
DATABASE="ecommerce"

echo "=== PostgreSQL Logical Backup ==="
echo "Timestamp: ${TIMESTAMP}"
echo "Database: ${DATABASE}"

mkdir -p "${BACKUP_DIR}"

# Backup entire database
echo "Backing up entire database..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  pg_dump -U postgres -d ${DATABASE} -F c -f /tmp/${DATABASE}_${TIMESTAMP}.dump

kubectl cp ${NAMESPACE}/${POD_NAME}:/tmp/${DATABASE}_${TIMESTAMP}.dump \
  "${BACKUP_DIR}/${DATABASE}_${TIMESTAMP}.dump"

kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm /tmp/${DATABASE}_${TIMESTAMP}.dump

echo "✅ Full database backup completed"

# Backup individual tables for granular recovery
echo "Backing up individual tables..."
for table in users products orders order_items; do
  echo "  - Backing up table: ${table}"
  
  kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
    pg_dump -U postgres -d ${DATABASE} -t ${table} -F c \
    -f /tmp/${table}_${TIMESTAMP}.dump
  
  kubectl cp ${NAMESPACE}/${POD_NAME}:/tmp/${table}_${TIMESTAMP}.dump \
    "${BACKUP_DIR}/${table}_${TIMESTAMP}.dump"
  
  kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm /tmp/${table}_${TIMESTAMP}.dump
  
  echo "  ✅ Table ${table} backed up"
done

# Backup schema only (for reference)
echo "Backing up schema..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  pg_dump -U postgres -d ${DATABASE} -s -f /tmp/schema_${TIMESTAMP}.sql

kubectl cp ${NAMESPACE}/${POD_NAME}:/tmp/schema_${TIMESTAMP}.sql \
  "${BACKUP_DIR}/schema_${TIMESTAMP}.sql"

kubectl exec -n ${NAMESPACE} ${POD_NAME} -- rm /tmp/schema_${TIMESTAMP}.sql

# Create backup metadata
cat > "${BACKUP_DIR}/backup_info_${TIMESTAMP}.txt" <<EOF
Backup Type: Logical Backup
Timestamp: ${TIMESTAMP}
Database: ${DATABASE}
Tables: users, products, orders, order_items
Size: $(du -sh "${BACKUP_DIR}" | cut -f1)
Status: SUCCESS
EOF

# Cleanup old backups (keep last 14 days)
echo "Cleaning up old backups..."
find "${BACKUP_DIR}" -name "*.dump" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "*.sql" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "backup_info_*.txt" -mtime +14 -delete 2>/dev/null || true

echo "=== Logical Backup Complete ==="
echo "Backup location: ${BACKUP_DIR}"
