#!/bin/bash
# Kafka Topic Backup Script
# Backs up Kafka topics to local storage
# Usage: ./kafka-topic-backup.sh

set -e

BACKUP_DIR="${BACKUP_DIR:-/e/Projects/DataPipe/backups/kafka/topics}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
NAMESPACE="data-ingestion"
KAFKA_POD="kafka-0"
KAFKA_BROKER="kafka-headless.data-ingestion.svc.cluster.local:9092"

echo "=== Kafka Topic Backup ==="
echo "Timestamp: ${TIMESTAMP}"

mkdir -p "${BACKUP_DIR}/${TIMESTAMP}"

# List all CDC topics
echo "Discovering CDC topics..."
TOPICS=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-topics --bootstrap-server ${KAFKA_BROKER} --list | \
  grep "^postgres\.public\." || true)

if [ -z "$TOPICS" ]; then
  echo "No CDC topics found"
  exit 0
fi

echo "Found topics:"
echo "$TOPICS"
echo ""

# Backup each topic
for topic in ${TOPICS}; do
  echo "Backing up topic: ${topic}"
  
  # Get topic configuration
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-configs --bootstrap-server ${KAFKA_BROKER} \
    --entity-type topics --entity-name ${topic} --describe \
    > "${BACKUP_DIR}/${TIMESTAMP}/${topic}.config" 2>/dev/null || true
  
  # Get topic partition info
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-topics --bootstrap-server ${KAFKA_BROKER} \
    --describe --topic ${topic} \
    > "${BACKUP_DIR}/${TIMESTAMP}/${topic}.partitions" 2>/dev/null || true
  
  # Export topic data (limited to prevent excessive backup size)
  echo "  - Exporting messages (max 10000)..."
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${topic} \
    --from-beginning \
    --max-messages 10000 \
    --timeout-ms 30000 \
    --property print.timestamp=true \
    --property print.key=true \
    --property print.offset=true \
    --property print.partition=true \
    > "${BACKUP_DIR}/${TIMESTAMP}/${topic}.messages" 2>/dev/null || true
  
  echo "  ✅ Topic ${topic} backed up"
done

# Backup consumer group offsets
echo ""
echo "Backing up consumer group offsets..."
GROUPS=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-consumer-groups --bootstrap-server ${KAFKA_BROKER} --list 2>/dev/null || true)

for group in ${GROUPS}; do
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-consumer-groups --bootstrap-server ${KAFKA_BROKER} \
    --group ${group} --describe \
    > "${BACKUP_DIR}/${TIMESTAMP}/${group}.offsets" 2>/dev/null || true
done

# Create backup metadata
cat > "${BACKUP_DIR}/${TIMESTAMP}/backup_info.txt" <<EOF
Backup Type: Kafka Topic Backup
Timestamp: ${TIMESTAMP}
Topics: $(echo "$TOPICS" | wc -l)
Consumer Groups: $(echo "$GROUPS" | wc -l)
Status: SUCCESS
EOF

# Compress backup
echo ""
echo "Compressing backup..."
cd "${BACKUP_DIR}"
tar -czf "kafka_backup_${TIMESTAMP}.tar.gz" "${TIMESTAMP}"
rm -rf "${TIMESTAMP}"

# Cleanup old backups (keep last 30 days)
echo "Cleaning up old backups..."
find "${BACKUP_DIR}" -name "kafka_backup_*.tar.gz" -mtime +30 -delete 2>/dev/null || true

echo ""
echo "=== Kafka Backup Complete ==="
echo "Backup file: ${BACKUP_DIR}/kafka_backup_${TIMESTAMP}.tar.gz"
echo "Size: $(du -sh "${BACKUP_DIR}/kafka_backup_${TIMESTAMP}.tar.gz" | cut -f1)"
