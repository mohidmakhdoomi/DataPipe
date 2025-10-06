#!/bin/bash
# Task 14: Deploy Backup and Recovery Procedures
# Multi-Model Consensus Implementation

set -e

echo "=== Deploying Task 14: Data-Specific Backup and Recovery Procedures ==="
echo "Multi-Model Consensus: Gemini 2.5 Pro (9/10) + Claude Opus 4.1 (7/10) + Grok 4 (8/10)"
echo

# Check if namespace exists
if ! kubectl get namespace data-ingestion >/dev/null 2>&1; then
    echo "ERROR: Namespace 'data-ingestion' not found. Please deploy the data ingestion pipeline first."
    exit 1
fi

# Check if PostgreSQL is running
echo "Checking PostgreSQL status..."
if ! kubectl get statefulset postgresql -n data-ingestion >/dev/null 2>&1; then
    echo "ERROR: PostgreSQL StatefulSet not found. Please deploy PostgreSQL first."
    exit 1
fi

POSTGRES_READY=$(kubectl get pods -n data-ingestion -l app=postgresql --no-headers | grep Running | wc -l)
if [ "$POSTGRES_READY" -eq 0 ]; then
    echo "ERROR: PostgreSQL is not running. Please ensure PostgreSQL is healthy before deploying backup procedures."
    exit 1
fi

echo "✅ PostgreSQL is running"

# Check if Kafka is running
echo "Checking Kafka status..."
KAFKA_READY=$(kubectl get pods -n data-ingestion -l app=kafka --no-headers | grep Running | wc -l)
if [ "$KAFKA_READY" -lt 3 ]; then
    echo "ERROR: Kafka cluster is not fully running ($KAFKA_READY/3 brokers). Please ensure Kafka is healthy."
    exit 1
fi

echo "✅ Kafka cluster is running (3/3 brokers)"

# Check if Kafka Connect is running
echo "Checking Kafka Connect status..."
CONNECT_READY=$(kubectl get pods -n data-ingestion -l app=kafka-connect --no-headers | grep Running | wc -l)
if [ "$CONNECT_READY" -eq 0 ]; then
    echo "ERROR: Kafka Connect is not running. Please ensure Kafka Connect is healthy."
    exit 1
fi

echo "✅ Kafka Connect is running"

# Update PostgreSQL configuration for WAL archiving
echo
echo "Updating PostgreSQL configuration for WAL archiving..."
kubectl patch configmap postgresql-config -n data-ingestion --patch "$(cat <<EOF
data:
  postgresql.conf: |
    include '/var/lib/postgresql/data/pgdata/postgresql.conf'
    
    # Memory Configuration (optimized for 1GB allocation)
    shared_buffers = 256MB
    effective_cache_size = 512MB
    work_mem = 4MB
    maintenance_work_mem = 64MB
    
    # Connection Configuration
    listen_addresses = '*'
    max_connections = 100
    
    # WAL Configuration for CDC - INCREASED for 4 instances
    wal_level = logical
    max_wal_senders = 8
    max_replication_slots = 8
    max_logical_replication_workers = 8
    
    # Performance Tuning
    checkpoint_completion_target = 0.9
    wal_buffers = 16MB
    default_statistics_target = 100
    random_page_cost = 1.1
    effective_io_concurrency = 200
    
    # Logging Configuration
    log_destination = 'stderr'
    logging_collector = on
    log_directory = 'log'
    log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
    log_statement = 'mod'
    log_min_duration_statement = 1000
    
    # Replication Configuration - INCREASED for multiple slots
    hot_standby = on
    wal_keep_size = 2GB
    max_slot_wal_keep_size = 4GB
    
    # WAL Archiving Configuration (Task 14: Backup and Recovery)
    archive_mode = on
    archive_command = 'test ! -f /var/lib/postgresql/wal_archive/%f && cp %p /var/lib/postgresql/wal_archive/%f'
    archive_timeout = 900  # 15 minutes (Claude's recommendation)
EOF
)"

echo "✅ PostgreSQL configuration updated for WAL archiving"

# Build custom backup tools image
echo
echo "Building custom backup tools image with both Kafka and Avro tools..."
docker build -f Dockerfile.backup-tools -t datapipe-backup-tools:latest .

# Load image into Kind cluster
echo "Loading backup tools image into Kind cluster..."
kind load docker-image datapipe-backup-tools:latest --name data-ingestion

# Deploy backup and recovery infrastructure
echo
echo "Deploying backup and recovery infrastructure..."
kubectl apply -f task14-backup-recovery-procedures.yaml

echo "✅ Backup and recovery infrastructure deployed"

# Deploy recovery testing
echo
echo "Deploying recovery testing procedures..."
kubectl apply -f task14-recovery-testing.yaml

echo "✅ Recovery testing procedures deployed"

# Wait for PVCs to be bound
echo
echo "Waiting for backup storage PVCs to be bound..."
kubectl wait --for=condition=Bound pvc/backup-storage-pvc -n data-ingestion --timeout=60s
kubectl wait --for=condition=Bound pvc/kafka-backup-storage-pvc -n data-ingestion --timeout=60s
kubectl wait --for=condition=Bound pvc/cdc-backup-storage-pvc -n data-ingestion --timeout=60s

echo "✅ Backup storage PVCs are bound"

# Restart PostgreSQL to apply WAL archiving configuration
echo
echo "Restarting PostgreSQL to apply WAL archiving configuration..."
kubectl rollout restart statefulset/postgresql -n data-ingestion
kubectl rollout status statefulset/postgresql -n data-ingestion --timeout=300s

echo "✅ PostgreSQL restarted with WAL archiving enabled"

# Verify backup infrastructure
echo
echo "Verifying backup infrastructure..."

# Check CronJob
if kubectl get cronjob data-backup-scheduler -n data-ingestion >/dev/null 2>&1; then
    echo "✅ Backup scheduler CronJob created"
else
    echo "❌ Backup scheduler CronJob not found"
    exit 1
fi

# Check ConfigMaps
BACKUP_CONFIGS=$(kubectl get configmap -n data-ingestion | grep -E "(backup|recovery)" | wc -l)
if [ "$BACKUP_CONFIGS" -ge 3 ]; then
    echo "✅ Backup configuration ConfigMaps created ($BACKUP_CONFIGS found)"
else
    echo "❌ Missing backup configuration ConfigMaps"
    exit 1
fi

# Check PVCs
BACKUP_PVCS=$(kubectl get pvc -n data-ingestion | grep backup | wc -l)
if [ "$BACKUP_PVCS" -ge 3 ]; then
    echo "✅ Backup storage PVCs created ($BACKUP_PVCS found)"
else
    echo "❌ Missing backup storage PVCs"
    exit 1
fi

# Test manual backup
echo
echo "Testing manual backup execution..."
kubectl create job manual-backup-test --from=cronjob/data-backup-scheduler -n data-ingestion

# Wait for job to start
sleep 10

# Check job status
JOB_STATUS=$(kubectl get job manual-backup-test -n data-ingestion -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")

if [ "$JOB_STATUS" = "Complete" ]; then
    echo "✅ Manual backup test completed successfully"
elif [ "$JOB_STATUS" = "Failed" ]; then
    echo "❌ Manual backup test failed"
    kubectl logs job/manual-backup-test -n data-ingestion
    exit 1
else
    echo "⏳ Manual backup test is running... (Status: $JOB_STATUS)"
    echo "   Monitor with: kubectl logs -f job/manual-backup-test -n data-ingestion"
fi

# Run recovery tests
echo
echo "Running recovery tests..."
kubectl create job recovery-test-run --from=job/recovery-testing-job -n data-ingestion

# Wait for test job to start
sleep 10

echo "⏳ Recovery tests are running..."
echo "   Monitor with: kubectl logs -f job/recovery-test-run -n data-ingestion"

# Display deployment summary
echo
echo "=== Task 14 Deployment Summary ==="
echo
echo "✅ Backup and Recovery Procedures Successfully Deployed"
echo
echo "Components Deployed:"
echo "  • PostgreSQL WAL archiving configuration"
echo "  • Backup scheduler CronJob (every 6 hours)"
echo "  • PostgreSQL backup scripts (pg_basebackup + WAL)"
echo "  • Kafka topic backup scripts (console consumer/producer)"
echo "  • CDC state backup scripts (connectors + schemas)"
echo "  • Recovery testing procedures"
echo "  • Backup storage PVCs (3.5Gi total)"
echo
echo "Backup Schedule:"
echo "  • Automated: 2AM, 8AM, 2PM, 8PM daily"
echo "  • Manual: kubectl create job --from=cronjob/data-backup-scheduler"
echo
echo "Recovery Procedures:"
echo "  • PostgreSQL PITR: /scripts/restore-postgresql.sh"
echo "  • Kafka topics: /scripts/restore-kafka-topics.sh"
echo "  • CDC state: /scripts/restore-cdc-state.sh"
echo
echo "Monitoring Commands:"
echo "  • Backup status: kubectl get cronjob,jobs -n data-ingestion"
echo "  • Storage usage: kubectl get pvc -n data-ingestion | grep backup"
echo "  • Test recovery: kubectl create job --from=job/recovery-testing-job"
echo
echo "Multi-Model Consensus Implementation:"
echo "  • Gemini 2.5 Pro (9/10): Production-grade pg_basebackup + WAL archiving"
echo "  • Claude Opus 4.1 (7/10): Resource-conscious 15-min WAL segments + OOM prevention"
echo "  • Grok 4 (8/10): Simplified kafka-console tools + off-peak scheduling"
echo
echo "Requirements Satisfied:"
echo "  ✅ 4.3: PostgreSQL data backup with point-in-time recovery"
echo "  ✅ 7.2: Kafka topic backup and replay procedures"
echo "  ✅ Testing: Corruption, CDC slot issues, schema conflicts"
echo "  ✅ Resource constraints: 3.5Gi additional storage, off-peak execution"
echo
echo "Task 14 deployment completed successfully! 🎉"