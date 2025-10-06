# Data Ingestion Pipeline - Backup and Recovery Scripts

This directory contains backup and recovery scripts for the data ingestion pipeline components.

## Prerequisites

- kubectl configured with access to the `data-ingestion` namespace
- Bash shell (Git Bash on Windows, or WSL)
- Sufficient disk space for backups (~100GB recommended)

## Directory Structure

```
scripts/
├── README.md                              # This file
├── postgresql-base-backup.sh              # PostgreSQL physical backup
├── postgresql-logical-backup.sh           # PostgreSQL logical backup (pg_dump)
├── postgresql-pitr-restore.sh             # Point-in-time recovery
├── kafka-topic-backup.sh                  # Kafka topic backup
├── kafka-topic-replay.sh                  # Kafka topic replay
├── cdc-replication-slot-backup.sh         # CDC slot metadata backup
├── cdc-replication-slot-restore.sh        # CDC slot recreation
└── validate-backups.sh                    # Backup validation tests
```

## Quick Start

### 1. Make Scripts Executable

```bash
cd /e/Projects/DataPipe/1-data-ingestion-pipeline/scripts
chmod +x *.sh
```

### 2. Set Backup Directory (Optional)

```bash
export BACKUP_DIR="/e/Projects/DataPipe/backups"
```

### 3. Run Your First Backup

```bash
# PostgreSQL logical backup (recommended for first test)
./postgresql-logical-backup.sh

# Validate the backup
./validate-backups.sh
```

## Backup Scripts

### PostgreSQL Base Backup

**Purpose**: Full physical backup for disaster recovery

```bash
./postgresql-base-backup.sh
```

**Output**: `/backups/postgresql/base/YYYYMMDD_HHMMSS/`
- `base.tar.gz` - Database files
- `pg_wal.tar.gz` - WAL files
- `backup_info.txt` - Metadata

**Retention**: 7 days

### PostgreSQL Logical Backup

**Purpose**: Schema and data backup for table-level recovery

```bash
./postgresql-logical-backup.sh
```

**Output**: `/backups/postgresql/logical/`
- `ecommerce_YYYYMMDD_HHMMSS.dump` - Full database
- `users_YYYYMMDD_HHMMSS.dump` - Users table
- `products_YYYYMMDD_HHMMSS.dump` - Products table
- `orders_YYYYMMDD_HHMMSS.dump` - Orders table
- `order_items_YYYYMMDD_HHMMSS.dump` - Order items table
- `schema_YYYYMMDD_HHMMSS.sql` - Schema only

**Retention**: 14 days

### Kafka Topic Backup

**Purpose**: Backup Kafka topics for replay and disaster recovery

```bash
./kafka-topic-backup.sh
```

**Output**: `/backups/kafka/topics/kafka_backup_YYYYMMDD_HHMMSS.tar.gz`

**Contents**:
- Topic configurations
- Partition information
- Message data (limited to 10,000 messages per topic)
- Consumer group offsets

**Retention**: 30 days

### CDC Replication Slot Backup

**Purpose**: Preserve CDC state for recovery

```bash
./cdc-replication-slot-backup.sh
```

**Output**: `/backups/postgresql/replication_slots/`
- `replication_slots_YYYYMMDD_HHMMSS.txt` - Slot details
- `slot_positions_YYYYMMDD_HHMMSS.csv` - LSN positions
- `wal_status_YYYYMMDD_HHMMSS.txt` - WAL status
- `publications_YYYYMMDD_HHMMSS.txt` - Publication info

**Retention**: 14 days

## Recovery Scripts

### Point-in-Time Recovery (PITR)

**Purpose**: Restore database to a specific point in time

```bash
./postgresql-pitr-restore.sh <backup_path> <target_time>
```

**Example**:
```bash
./postgresql-pitr-restore.sh \
  /e/Projects/DataPipe/backups/postgresql/base/20250106_020000 \
  '2025-01-06 14:30:00'
```

**⚠️ Warning**: This will stop and restore PostgreSQL. All CDC connectors should be stopped first.

### Kafka Topic Replay

**Purpose**: Replay messages from one topic to another

```bash
./kafka-topic-replay.sh <source_topic> <target_topic> [start_timestamp] [end_timestamp]
```

**Examples**:
```bash
# Full replay
./kafka-topic-replay.sh postgres.public.users postgres.public.users_replay

# Time-range replay (timestamps in milliseconds)
./kafka-topic-replay.sh \
  postgres.public.users \
  postgres.public.users_replay \
  1704556800000 \
  1704643200000
```

### CDC Replication Slot Restore

**Purpose**: Recreate replication slots after database restore

```bash
./cdc-replication-slot-restore.sh <slot_name> [lsn_position]
```

**Examples**:
```bash
# Create new slot
./cdc-replication-slot-restore.sh debezium_slot_users

# Restore to specific LSN
./cdc-replication-slot-restore.sh debezium_slot_users 0/1A2B3C4D
```

## Validation

### Run Backup Validation Tests

```bash
./validate-backups.sh
```

**Tests Include**:
- Backup directory structure
- Backup file integrity
- PostgreSQL connectivity
- Kafka connectivity
- Replication slot status
- Script permissions

**Expected Output**:
```
=========================================
  Backup Validation Test Suite
=========================================

=== Infrastructure Tests ===
Test: PostgreSQL base backup directory exists... ✅ PASS
Test: PostgreSQL logical backup directory exists... ✅ PASS
...

=========================================
  Test Summary
=========================================
Passed: 20
Failed: 0
Total:  20

✅ All tests passed!
```

## Automated Backups

### Deploy CronJobs

```bash
kubectl apply -f /e/Projects/DataPipe/1-data-ingestion-pipeline/backup-cronjobs.yaml
```

**Schedule**:
- PostgreSQL Base Backup: Daily at 2:00 AM UTC
- PostgreSQL Logical Backup: Daily at 3:00 AM UTC
- CDC Replication Slot Backup: Daily at 4:00 AM UTC

### Monitor CronJobs

```bash
# List CronJobs
kubectl get cronjobs -n data-ingestion

# View job history
kubectl get jobs -n data-ingestion

# Check logs
kubectl logs -n data-ingestion job/postgresql-base-backup-<timestamp>
```

## Recovery Scenarios

### Scenario 1: Table Corruption

**Symptoms**: Specific table has corrupted data

**Recovery**:
```bash
# 1. Identify latest logical backup
ls -lt /e/Projects/DataPipe/backups/postgresql/logical/users_*.dump | head -1

# 2. Copy backup to pod
kubectl cp /e/Projects/DataPipe/backups/postgresql/logical/users_20250106_030000.dump \
  data-ingestion/postgresql-0:/tmp/users_backup.dump

# 3. Restore table
kubectl exec -n data-ingestion postgresql-0 -- \
  pg_restore -U postgres -d ecommerce -t users --clean --if-exists \
  /tmp/users_backup.dump
```

### Scenario 2: Database Corruption

**Symptoms**: Database reports corruption errors, queries fail

**Recovery**:
```bash
# 1. Stop CDC connectors
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-users-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-products-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-orders-connector
curl -X DELETE http://localhost:8083/connectors/postgres-cdc-order-items-connector

# 2. Restore database
./postgresql-pitr-restore.sh \
  /e/Projects/DataPipe/backups/postgresql/base/20250106_020000 \
  '2025-01-06 14:00:00'

# 3. Recreate replication slots
./cdc-replication-slot-restore.sh debezium_slot_users
./cdc-replication-slot-restore.sh debezium_slot_products
./cdc-replication-slot-restore.sh debezium_slot_orders
./cdc-replication-slot-restore.sh debezium_slot_order_items

# 4. Restart CDC connectors
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @/e/Projects/DataPipe/1-data-ingestion-pipeline/connectors/users-debezium-connector.json
```

### Scenario 3: Kafka Topic Data Loss

**Symptoms**: Missing events in Kafka topics

**Recovery**:
```bash
# 1. Verify data loss
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list kafka-headless.data-ingestion.svc.cluster.local:9092 \
  --topic postgres.public.users

# 2. Replay from backup
./kafka-topic-replay.sh postgres.public.users postgres.public.users_restored

# 3. Verify restoration
kubectl exec -n data-ingestion kafka-0 -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list kafka-headless.data-ingestion.svc.cluster.local:9092 \
  --topic postgres.public.users_restored
```

### Scenario 4: CDC Replication Slot Lag

**Symptoms**: Replication slot lag increasing, WAL disk space filling

**Recovery**:
```bash
# 1. Check slot status
kubectl exec -n data-ingestion postgresql-0 -- \
  psql -U postgres -d ecommerce -c \
  "SELECT slot_name, active, restart_lsn, 
   pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag 
   FROM pg_replication_slots;"

# 2. Restart Kafka Connect
kubectl rollout restart deployment/kafka-connect -n data-ingestion

# 3. If slot is stuck, recreate it
./cdc-replication-slot-restore.sh debezium_slot_users
```

## Troubleshooting

### Backup Script Fails

**Check**:
1. Kubernetes connectivity: `kubectl get pods -n data-ingestion`
2. Disk space: `df -h /e/Projects/DataPipe/backups`
3. Pod status: `kubectl describe pod postgresql-0 -n data-ingestion`

### Restore Fails

**Check**:
1. Backup file integrity: `tar -tzf backup.tar.gz`
2. PostgreSQL logs: `kubectl logs -n data-ingestion postgresql-0`
3. Disk space in pod: `kubectl exec -n data-ingestion postgresql-0 -- df -h`

### Validation Tests Fail

**Common Issues**:
- Backup directories don't exist: Create them manually
- No backups found: Run backup scripts first
- Pods not running: Check cluster status

## Best Practices

1. **Test Restores Regularly**: Run quarterly recovery drills
2. **Monitor Backup Size**: Alert on anomalies
3. **Verify Backups**: Run validation after each backup
4. **Document Changes**: Update procedures when architecture changes
5. **Secure Backups**: Encrypt sensitive backup data
6. **Off-site Storage**: Copy critical backups to S3 or external storage

## Storage Requirements

- **PostgreSQL Base Backups**: ~5GB per backup × 7 days = 35GB
- **PostgreSQL Logical Backups**: ~2GB per backup × 14 days = 28GB
- **Kafka Topic Backups**: ~5GB per backup × 4 weeks = 20GB
- **Replication Slot Metadata**: <100MB
- **Total**: ~85GB + buffer = **100GB recommended**

## Support

For issues or questions:
1. Check logs: `kubectl logs -n data-ingestion <pod-name>`
2. Review documentation: `/e/Projects/DataPipe/1-data-ingestion-pipeline/backup-recovery-procedures.md`
3. Contact: DevOps team

## References

- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/current/backup.html)
- [Kafka Operations](https://kafka.apache.org/documentation/#operations)
- [Debezium Monitoring](https://debezium.io/documentation/reference/stable/operations/monitoring.html)
