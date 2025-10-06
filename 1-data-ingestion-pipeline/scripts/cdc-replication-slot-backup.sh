#!/bin/bash
# CDC Replication Slot Backup Script
# Backs up PostgreSQL replication slot metadata
# Usage: ./cdc-replication-slot-backup.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-/e/Projects/DataPipe/backups/postgresql/replication_slots}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAMESPACE="data-ingestion"
POD_NAME="postgresql-0"

echo "=== CDC Replication Slot Backup ==="
echo "Timestamp: ${TIMESTAMP}"

mkdir -p "${BACKUP_DIR}"

# List all replication slots
echo "Backing up replication slot information..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c \
  "SELECT slot_name, plugin, slot_type, database, active, restart_lsn, confirmed_flush_lsn, 
   pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag
   FROM pg_replication_slots;" \
  > "${BACKUP_DIR}/replication_slots_${TIMESTAMP}.txt"

# Backup slot positions in CSV format
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -t -A -F',' -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn, active
   FROM pg_replication_slots 
   WHERE slot_name LIKE 'debezium_slot%';" \
  > "${BACKUP_DIR}/slot_positions_${TIMESTAMP}.csv"

# Backup WAL status
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c \
  "SELECT pg_current_wal_lsn() AS current_lsn, 
   pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;" \
  > "${BACKUP_DIR}/wal_status_${TIMESTAMP}.txt"

# Backup publication information
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c \
  "SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete 
   FROM pg_publication 
   WHERE pubname LIKE 'dbz_publication%';" \
  > "${BACKUP_DIR}/publications_${TIMESTAMP}.txt"

# Create backup metadata
cat > "${BACKUP_DIR}/backup_info_${TIMESTAMP}.txt" <<EOF
Backup Type: CDC Replication Slot Backup
Timestamp: ${TIMESTAMP}
Database: ecommerce
Status: SUCCESS
EOF

# Create latest symlink
ln -sf "replication_slots_${TIMESTAMP}.txt" "${BACKUP_DIR}/replication_slots_latest.txt"
ln -sf "slot_positions_${TIMESTAMP}.csv" "${BACKUP_DIR}/slot_positions_latest.csv"

# Cleanup old backups (keep last 14 days)
find "${BACKUP_DIR}" -name "*_20*.txt" -mtime +14 -delete 2>/dev/null || true
find "${BACKUP_DIR}" -name "*_20*.csv" -mtime +14 -delete 2>/dev/null || true

echo ""
echo "=== Replication Slot Backup Complete ==="
echo "Backup location: ${BACKUP_DIR}"
echo ""
echo "Slot Summary:"
cat "${BACKUP_DIR}/replication_slots_${TIMESTAMP}.txt"
