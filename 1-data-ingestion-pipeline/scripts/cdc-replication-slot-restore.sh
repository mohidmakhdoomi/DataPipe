#!/bin/bash
# CDC Replication Slot Restore Script
# Recreates replication slots after database restore
# Usage: ./cdc-replication-slot-restore.sh <slot_name> [lsn_position]

set -e

SLOT_NAME=$1
LSN_POSITION=$2
NAMESPACE="data-ingestion"
POD_NAME="postgresql-0"

if [ -z "$SLOT_NAME" ]; then
  echo "Usage: $0 <slot_name> [lsn_position]"
  echo ""
  echo "Examples:"
  echo "  Create new slot:     $0 debezium_slot_users"
  echo "  Restore to LSN:      $0 debezium_slot_users 0/1A2B3C4D"
  echo ""
  echo "Available slots from backup:"
  if [ -f "/e/Projects/DataPipe/backups/postgresql/replication_slots/slot_positions_latest.csv" ]; then
    cat "/e/Projects/DataPipe/backups/postgresql/replication_slots/slot_positions_latest.csv"
  fi
  exit 1
fi

echo "=== CDC Replication Slot Restore ==="
echo "Slot Name: ${SLOT_NAME}"
if [ -n "$LSN_POSITION" ]; then
  echo "LSN Position: ${LSN_POSITION}"
fi
echo ""

# Check if slot already exists
SLOT_EXISTS=$(kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -t -c \
  "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = '${SLOT_NAME}';" | tr -d ' ')

if [ "$SLOT_EXISTS" -gt 0 ]; then
  echo "Slot '${SLOT_NAME}' already exists"
  read -p "Drop and recreate? (yes/no): " confirm
  
  if [ "$confirm" = "yes" ]; then
    echo "Dropping existing slot..."
    kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
      psql -U postgres -d ecommerce -c \
      "SELECT pg_drop_replication_slot('${SLOT_NAME}');"
    echo "✅ Slot dropped"
  else
    echo "Aborted"
    exit 0
  fi
fi

# Create new replication slot
echo "Creating replication slot..."
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c \
  "SELECT pg_create_logical_replication_slot('${SLOT_NAME}', 'pgoutput');"

echo "✅ Replication slot created"

# Advance slot to specific LSN if provided
if [ -n "$LSN_POSITION" ]; then
  echo "Advancing slot to LSN: ${LSN_POSITION}"
  kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
    psql -U postgres -d ecommerce -c \
    "SELECT pg_replication_slot_advance('${SLOT_NAME}', '${LSN_POSITION}');"
  echo "✅ Slot advanced to specified LSN"
fi

# Verify slot status
echo ""
echo "Slot Status:"
kubectl exec -n ${NAMESPACE} ${POD_NAME} -- \
  psql -U postgres -d ecommerce -c \
  "SELECT slot_name, plugin, active, restart_lsn, confirmed_flush_lsn 
   FROM pg_replication_slots 
   WHERE slot_name = '${SLOT_NAME}';"

echo ""
echo "=== Replication Slot Restore Complete ==="
