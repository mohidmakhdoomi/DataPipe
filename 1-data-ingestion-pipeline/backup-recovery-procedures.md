# Data Ingestion Pipeline - Backup and Recovery Procedures

## Overview

This document provides comprehensive backup and recovery procedures for the data ingestion pipeline, covering PostgreSQL data, Kafka topics, and CDC replication slots. These procedures ensure data protection and enable recovery from various failure scenarios.

## Table of Contents

1. [PostgreSQL Backup and Recovery](#postgresql-backup-and-recovery)
2. [Kafka Topic Backup and Replay](#kafka-topic-backup-and-replay)
3. [CDC Replication Slot Management](#cdc-replication-slot-management)
4. [Recovery Scenarios](#recovery-scenarios)
5. [Backup Schedule and Retention](#backup-schedule-and-retention)
6. [Testing and Validation](#testing-and-validation)

---

## PostgreSQL Backup and Recovery

### Backup Strategy

The PostgreSQL backup strategy uses a combination of:
- **Base backups**: Full physical backups using `pg_basebackup`
- **WAL archiving**: Continuous archiving of Write-Ahead Logs for point-in-time recovery
- **Logical backups**: Schema and data dumps using `pg_dump` for specific tables

### 1.1 Base Backup Procedure

**Frequency**: Daily at 2:00 AM UTC  
**Retention**: 7 days

```bash
#!/bin/bash
# File: scripts/postgresql-base-backup.sh

BACKUP_DIR="/backups/postgresql/base"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Perform base backup
kubectl exec -n data-ingestion postgresql-0 -- \
  pg_basebackup -D /tmp/backup -F tar -z -P -U postgres

# Copy backup from pod to local storage
kubectl cp data-ingestion/postgresql-0:/tmp/backup "${BACKUP_PATH}"

# Verify backup integrity
tar -tzf "${BACKUP_PATH}/base.tar.gz" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "Backup completed successfully: ${BACKUP_PATH}"
else
  echo "ERROR: Backup verification failed"
  exit 1
fi

# Cleanup old backups (keep last 7 days)
find "${BACKUP_DIR}" -type d -mtime +7 -exec rm -rf {} \;
```

### 1.2 WAL Archiving Configuration

**Purpose**: Enable point-in-time recovery (PITR)

Add to PostgreSQL ConfigMap:
```yaml
# WAL Archiving Configuration
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/wal_archive/%f && cp %p /var/lib/postgresql/wal_archive/%f'
archive_timeout = 300  # Archive every 5 minutes
wal_keep_size = 2GB
max_slot_wal_keep_size = 4GB
```

### 1.3 Logical Backup (Schema + Data)

**Frequency**: Daily at 3:00 AM UTC  
**Retention**: 14 days

```bash
#!/bin/bash
# File: scripts/postgresql-logical-backup.sh

BACKUP_DIR="/backups/postgresql/logical"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATABASE="ecommerce"

mkdir -p "${BACKUP_DIR}"

# Backup entire database
kubectl exec -n data-ingestion postgresql-0 -- \
  pg_dump -U postgres -d ${DATABASE} -F c -f /tmp/${DATABASE}_${TIMESTAMP}.dump

# Copy backup from pod
kubectl cp data-ingestion/postgresql-0:/tmp/${DATABASE}_${TIMESTAMP}.dump \
  "${BACKUP_DIR}/${DATABASE}_${TIMESTAMP}.dump"

# Backup individual tables for granular recovery
for table in users products orders order_items; do
  kubectl exec -n data-ingestion postgresql-0 -- \
    pg_dump -U postgres -d ${DATABASE} -t ${table} -F c \
    -f /tmp/${table}_${TIMESTAMP}.dump
  
  kubectl cp data-ingestion/postgresql-0:/tmp/${table}_${TIMESTAMP}.dump \
    "${BACKUP_DIR}/${table}_${TIMESTAMP}.dump"
done

# Cleanup old backups (keep last 14 days)
find "${BACKUP_DIR}" -name "*.dump" -mtime +14 -delete

echo "Logical backup completed: ${BACKUP_DIR}"
```

### 1.4 Point-in-Time Recovery (PITR)

**Scenario**: Restore database to a specific point in time

```bash
#!/bin/bash
# File: scripts/postgresql-pitr-restore.sh

BACKUP_PATH=$1
TARGET_TIME=$2  # Format: 'YYYY-MM-DD HH:MM:SS'

if [ -z "$BACKUP_PATH" ] || [ -z "$TARGET_TIME" ]; then
  echo "Usage: $0 <backup_path> <target_time>"
  echo "Example: $0 /backups/postgresql/base/20250106_020000 '2025-01-06 14:30:00'"
  exit 1
fi

# Stop PostgreSQL
kubectl scale statefulset postgresql -n data-ingestion --replicas=0

# Wait for pod to terminate
kubectl wait --for=delete pod/postgresql-0 -n data-ingestion --timeout=60s

# Restore base backup
kubectl exec -n data-ingestion postgresql-0 -- rm -rf /var/lib/postgresql/data/pgdata/*
kubectl cp "${BACKUP_PATH}/base.tar.gz" data-ingestion/postgresql-0:/tmp/base.tar.gz
kubectl exec -n data-ingestion postgresql-0 -- \
  tar -xzf /tmp/base.tar.gz -C /var/lib/postgresql/data/pgdata

# Create recovery configuration
cat > /tmp/recovery.conf <<EOF
restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
recovery_target_time = '${TARGET_TIME}'
recovery_target_action = 'promote'
EOF

kubectl cp /tmp/recovery.conf data-ingestion/postgresql-0:/var/lib/postgresql/data/pgdata/recovery.conf

# Start PostgreSQL
kubectl scale statefulset postgresql -n data-ingestion --replicas=1

# Wait for recovery to complete
kubectl wait --for=condition=ready pod/postgresql-0 -n data-ingestion --timeout=300s

echo "PITR restore completed to: ${TARGET_TIME}"
```

### 1.5 Table-Level Recovery

**Scenario**: Restore a single table without affecting others

```bash
#!/bin/bash
# File: scripts/postgresql-table-restore.sh

TABLE_NAME=$1
BACKUP_FILE=$2

if [ -z "$TABLE_NAME" ] || [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <table_name> <backup_file>"
  exit 1
fi

# Copy backup to pod
kubectl cp "${BACKUP_FILE}" data-ingestion/postgresql-0:/tmp/table_backup.dump

# Drop and recreate table (with confirmation)
read -p "This will DROP table ${TABLE_NAME}. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
  echo "Aborted"
  exit 0
fi

# Restore table
kubectl exec -n data-ingestion postgresql-0 -- \
  pg_restore -U postgres -d ecommerce -t ${TABLE_NAME} --clean --if-exists \
  /tmp/table_backup.dump

echo "Table ${TABLE_NAME} restored successfully"
```

---

## Kafka Topic Backup and Replay

### Backup Strategy

Kafka topic backups enable:
- **Disaster recovery**: Restore topics after cluster failure
- **Data replay**: Reprocess events from specific time ranges
- **Audit compliance**: Maintain historical event records

### 2.1 Kafka Topic Backup (Mirror Maker 2)

**Frequency**: Continuous replication to backup cluster (optional)  
**Alternative**: Periodic snapshots to S3

```bash
#!/bin/bash
# File: scripts/kafka-topic-backup.sh

BACKUP_DIR="/backups/kafka/topics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KAFKA_BROKER="kafka-0.kafka-headless.data-ingestion.svc.cluster.local:9092"

mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"

# List all CDC topics
TOPICS=$(kubectl exec -n data-ingestion kafka-0 -- \
  kafka-topics --bootstrap-server ${KAFKA_BROKER} --list | \
  grep "^postgres\.public\.")

# Backup each topic
for topic in ${TOPICS}; do
  echo "Backing up topic: ${topic}"
  
  # Export topic data to JSON
  kubectl exec -n data-ingestion kafka-0 -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${topic} \
    --from-beginning \
    --max-messages 100000 \
    --timeout-ms 30000 > "${BACKUP_DIR}/${TIMESTAMP}/${topic}.json"
  
  # Backup topic configuration
  kubectl exec -n data-ingestion kafka-0 -- \
    kafka-configs --bootstrap-server ${KAFKA_BROKER} \
    --entity-type topics --entity-name ${topic} --describe \
    > "${BACKUP_DIR}/${TIMESTAMP}/${topic}.config"
done

# Compress backup
tar -czf "${BACKUP_DIR}/kafka_backup_${TIMESTAMP}.tar.gz" \
  -C "${BACKUP_DIR}" "${TIMESTAMP}"
rm -rf "${BACKUP_DIR}/${TIMESTAMP}"

echo "Kafka topic backup completed: ${BACKUP_DIR}/kafka_backup_${TIMESTAMP}.tar.gz"
```

### 2.2 Kafka Topic Replay

**Scenario**: Replay events from a specific time range

```bash
#!/bin/bash
# File: scripts/kafka-topic-replay.sh

SOURCE_TOPIC=$1
TARGET_TOPIC=$2
START_TIMESTAMP=$3  # Unix timestamp in milliseconds
END_TIMESTAMP=$4

if [ -z "$SOURCE_TOPIC" ] || [ -z "$TARGET_TOPIC" ]; then
  echo "Usage: $0 <source_topic> <target_topic> [start_timestamp] [end_timestamp]"
  exit 1
fi

KAFKA_BROKER="kafka-0.kafka-headless.data-ingestion.svc.cluster.local:9092"

# Create target topic if it doesn't exist
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-topics --bootstrap-server ${KAFKA_BROKER} \
  --create --if-not-exists --topic ${TARGET_TOPIC} \
  --partitions 6 --replication-factor 3

# Replay messages
if [ -n "$START_TIMESTAMP" ]; then
  # Time-based replay
  kubectl exec -n data-ingestion kafka-0 -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${SOURCE_TOPIC} \
    --property print.timestamp=true \
    --property print.key=true \
    --from-beginning | \
    awk -v start=${START_TIMESTAMP} -v end=${END_TIMESTAMP} \
    '$1 >= start && $1 <= end' | \
    kubectl exec -i -n data-ingestion kafka-0 -- \
    kafka-console-producer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${TARGET_TOPIC} \
    --property parse.key=true
else
  # Full replay
  kubectl exec -n data-ingestion kafka-0 -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${SOURCE_TOPIC} \
    --from-beginning | \
    kubectl exec -i -n data-ingestion kafka-0 -- \
    kafka-console-producer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${TARGET_TOPIC}
fi

echo "Topic replay completed: ${SOURCE_TOPIC} -> ${TARGET_TOPIC}"
```

### 2.3 Consumer Group Offset Backup

**Purpose**: Preserve consumer positions for recovery

```bash
#!/bin/bash
# File: scripts/kafka-consumer-offsets-backup.sh

BACKUP_DIR="/backups/kafka/offsets"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KAFKA_BROKER="kafka-0.kafka-headless.data-ingestion.svc.cluster.local:9092"

mkdir -p "${BACKUP_DIR}"

# List all consumer groups
GROUPS=$(kubectl exec -n data-ingestion kafka-0 -- \
  kafka-consumer-groups --bootstrap-server ${KAFKA_BROKER} --list)

# Backup offsets for each group
for group in ${GROUPS}; do
  kubectl exec -n data-ingestion kafka-0 -- \
    kafka-consumer-groups --bootstrap-server ${KAFKA_BROKER} \
    --group ${group} --describe \
    > "${BACKUP_DIR}/${group}_${TIMESTAMP}.offsets"
done

echo "Consumer group offsets backed up: ${BACKUP_DIR}"
```

---

## CDC Replication Slot Management

### 3.1 Replication Slot Backup

**Purpose**: Preserve CDC state for recovery

```bash
#!/bin/bash
# File: scripts/cdc-replication-slot-backup.sh

BACKUP_DIR="/backups/postgresql/replication_slots"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${BACKUP_DIR}"

# List all replication slots
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c \
  "SELECT slot_name, plugin, slot_type, database, active, restart_lsn, confirmed_flush_lsn 
   FROM pg_replication_slots;" \
  > "${BACKUP_DIR}/replication_slots_${TIMESTAMP}.txt"

# Backup slot metadata
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -t -c \
  "SELECT slot_name, restart_lsn, confirmed_flush_lsn 
   FROM pg_replication_slots 
   WHERE slot_name LIKE 'debezium_slot%';" \
  > "${BACKUP_DIR}/slot_positions_${TIMESTAMP}.csv"

echo "Replication slot backup completed: ${BACKUP_DIR}"
```

### 3.2 Replication Slot Recovery

**Scenario**: Recreate replication slots after database restore

```bash
#!/bin/bash
# File: scripts/cdc-replication-slot-restore.sh

SLOT_NAME=$1
LSN_POSITION=$2

if [ -z "$SLOT_NAME" ]; then
  echo "Usage: $0 <slot_name> [lsn_position]"
  exit 1
fi

# Drop existing slot if present
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c \
  "SELECT pg_drop_replication_slot('${SLOT_NAME}') 
   WHERE EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${SLOT_NAME}');"

# Create new replication slot
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c \
  "SELECT pg_create_logical_replication_slot('${SLOT_NAME}', 'pgoutput');"

# Advance slot to specific LSN if provided
if [ -n "$LSN_POSITION" ]; then
  kubectl exec -n data-ingestion postgresql-0 -- \
    psql -U postgres -d ecommerce -c \
    "SELECT pg_replication_slot_advance('${SLOT_NAME}', '${LSN_POSITION}');"
fi

echo "Replication slot ${SLOT_NAME} restored"
```

---

## Recovery Scenarios

### 4.1 Scenario: PostgreSQL Data Corruption

**Symptoms**: Database reports corruption errors, queries fail

**Recovery Steps**:
1. Stop all CDC connectors to prevent further data loss
2. Identify corruption extent using `pg_dump` validation
3. Restore from most recent base backup
4. Apply WAL logs up to corruption point
5. Verify data integrity
6. Restart CDC connectors

```bash
# Stop CDC connectors
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-users-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-products-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-orders-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-order-items-connector

# Restore database (use PITR script)
./scripts/postgresql-pitr-restore.sh /backups/postgresql/base/latest '2025-01-06 14:00:00'

# Verify data integrity
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c "SELECT COUNT(*) FROM users;"

# Restart CDC connectors
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @connectors/users-debezium-connector.json
```

### 4.2 Scenario: CDC Replication Slot Issues

**Symptoms**: Replication slot lag increasing, WAL disk space filling

**Recovery Steps**:
1. Check replication slot status
2. Identify lagging slots
3. Restart Kafka Connect workers
4. If slot is stuck, drop and recreate
5. Resume CDC from last known good position

```bash
# Check slot status
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c \
  "SELECT slot_name, active, restart_lsn, 
   pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag 
   FROM pg_replication_slots;"

# Restart Kafka Connect
kubectl rollout restart deployment/kafka-connect -n data-ingestion

# If slot is stuck, recreate it
./scripts/cdc-replication-slot-restore.sh debezium_slot_users
```

### 4.3 Scenario: Kafka Topic Data Loss

**Symptoms**: Missing events in Kafka topics, consumer lag spikes

**Recovery Steps**:
1. Verify data loss extent
2. Check S3 archive for missing data
3. Replay from PostgreSQL CDC if within WAL retention
4. Restore from Kafka backup if available
5. Validate data consistency

```bash
# Check topic message count
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list kafka-0.kafka-headless.data-ingestion.svc.cluster.local:9092 \
  --topic postgres.public.users

# Replay from backup
./scripts/kafka-topic-replay.sh postgres.public.users postgres.public.users_restored

# Verify S3 archive
aws s3 ls s3://your-bucket/topics/postgres.public.users/ --recursive
```

### 4.4 Scenario: Schema Registry Failure

**Symptoms**: Schema validation errors, connector failures

**Recovery Steps**:
1. Verify Schema Registry connectivity
2. Check `_schemas` topic integrity
3. Restore Schema Registry from Kafka topic
4. Re-register schemas if necessary
5. Restart connectors

```bash
# Check Schema Registry health
curl http://localhost:8081/subjects

# Verify _schemas topic
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-console-consumer \
  --bootstrap-server kafka-0.kafka-headless.data-ingestion.svc.cluster.local:9092 \
  --topic _schemas --from-beginning --max-messages 10

# Restart Schema Registry
kubectl rollout restart deployment/schema-registry -n data-ingestion
```

---

## Backup Schedule and Retention

### Backup Schedule

| Component         | Backup Type    | Frequency     | Retention | Storage Location                        |
| ----------------- | -------------- | ------------- | --------- | --------------------------------------- |
| PostgreSQL        | Base Backup    | Daily 2:00 AM | 7 days    | `/backups/postgresql/base`              |
| PostgreSQL        | Logical Backup | Daily 3:00 AM | 14 days   | `/backups/postgresql/logical`           |
| PostgreSQL        | WAL Archive    | Continuous    | 7 days    | `/backups/postgresql/wal_archive`       |
| Kafka Topics      | Snapshot       | Weekly        | 30 days   | `/backups/kafka/topics`                 |
| Consumer Offsets  | Snapshot       | Daily         | 7 days    | `/backups/kafka/offsets`                |
| Replication Slots | Metadata       | Daily         | 14 days   | `/backups/postgresql/replication_slots` |
| S3 Archive        | Native         | Continuous    | 90 days   | AWS S3 (versioning enabled)             |

### Retention Policy

- **Short-term**: 7 days for operational recovery
- **Medium-term**: 14-30 days for compliance and audit
- **Long-term**: 90+ days in S3 with lifecycle policies

---

## Testing and Validation

### 6.1 Backup Validation Tests

```bash
#!/bin/bash
# File: scripts/validate-backups.sh

echo "=== Backup Validation Test Suite ==="

# Test 1: PostgreSQL base backup integrity
echo "Test 1: Validating PostgreSQL base backup..."
LATEST_BACKUP=$(ls -t /backups/postgresql/base | head -1)
tar -tzf "/backups/postgresql/base/${LATEST_BACKUP}/base.tar.gz" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ PostgreSQL base backup is valid"
else
  echo "❌ PostgreSQL base backup is corrupted"
fi

# Test 2: Logical backup restore test
echo "Test 2: Testing logical backup restore..."
kubectl exec -n data-ingestion postgresql-0 -- \
  pg_restore --list /tmp/ecommerce_latest.dump > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Logical backup can be restored"
else
  echo "❌ Logical backup restore failed"
fi

# Test 3: Kafka topic backup validation
echo "Test 3: Validating Kafka topic backups..."
LATEST_KAFKA_BACKUP=$(ls -t /backups/kafka/topics/*.tar.gz | head -1)
tar -tzf "${LATEST_KAFKA_BACKUP}" > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✅ Kafka topic backup is valid"
else
  echo "❌ Kafka topic backup is corrupted"
fi

# Test 4: Replication slot metadata
echo "Test 4: Checking replication slot metadata..."
if [ -f "/backups/postgresql/replication_slots/slot_positions_latest.csv" ]; then
  echo "✅ Replication slot metadata exists"
else
  echo "❌ Replication slot metadata missing"
fi

echo "=== Validation Complete ==="
```

### 6.2 Recovery Drill Schedule

**Quarterly Recovery Drills**:
- Q1: PostgreSQL PITR recovery
- Q2: Kafka topic replay
- Q3: Full pipeline recovery (PostgreSQL + Kafka)
- Q4: Schema Registry recovery

### 6.3 Recovery Time Objectives (RTO)

| Scenario                 | Target RTO | Actual RTO (Tested) |
| ------------------------ | ---------- | ------------------- |
| PostgreSQL table restore | 15 minutes | TBD                 |
| PostgreSQL PITR          | 30 minutes | TBD                 |
| Kafka topic replay       | 20 minutes | TBD                 |
| CDC slot recreation      | 10 minutes | TBD                 |
| Full pipeline recovery   | 60 minutes | TBD                 |

### 6.4 Recovery Point Objectives (RPO)

| Component    | Target RPO | Notes                       |
| ------------ | ---------- | --------------------------- |
| PostgreSQL   | 5 minutes  | WAL archiving interval      |
| Kafka Topics | 0 minutes  | Replicated across 3 brokers |
| S3 Archive   | 60 seconds | Flush interval              |

---

## Automation and Monitoring

### Backup Automation (CronJob)

```yaml
# File: backup-cronjobs.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgresql-base-backup
  namespace: data-ingestion
spec:
  schedule: "0 2 * * *"  # Daily at 2:00 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:15-alpine
            command: ["/scripts/postgresql-base-backup.sh"]
            volumeMounts:
            - name: backup-scripts
              mountPath: /scripts
            - name: backup-storage
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-storage-pvc
```

### Backup Monitoring Alerts

- **Alert**: Backup job failed
- **Alert**: Backup size anomaly (too small/large)
- **Alert**: Backup age exceeds threshold
- **Alert**: Replication slot lag > 1GB
- **Alert**: WAL disk usage > 80%

---

## Appendix

### A. Backup Storage Requirements

- **PostgreSQL Base Backups**: ~5GB per backup × 7 days = 35GB
- **PostgreSQL Logical Backups**: ~2GB per backup × 14 days = 28GB
- **WAL Archives**: ~10GB for 7 days
- **Kafka Topic Backups**: ~5GB per backup × 4 weeks = 20GB
- **Total**: ~100GB local storage + S3 for long-term retention

### B. Useful Commands

```bash
# Check PostgreSQL backup status
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -c "SELECT pg_is_in_backup();"

# List replication slots
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c "SELECT * FROM pg_replication_slots;"

# Check Kafka topic retention
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-configs --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name postgres.public.users --describe

# Verify S3 archive
aws s3 ls s3://your-bucket/topics/ --recursive --human-readable
```

### C. Contact Information

- **On-Call Engineer**: [Contact details]
- **Database Administrator**: [Contact details]
- **DevOps Team**: [Contact details]

---

**Document Version**: 1.0  
**Last Updated**: 2025-01-06  
**Next Review**: 2025-04-06
