#!/bin/bash
# Kafka Topic Replay Script
# Replays messages from one topic to another
# Usage: ./kafka-topic-replay.sh <source_topic> <target_topic> [start_timestamp] [end_timestamp]

set -e

SOURCE_TOPIC=$1
TARGET_TOPIC=$2
START_TIMESTAMP=$3  # Unix timestamp in milliseconds (optional)
END_TIMESTAMP=$4    # Unix timestamp in milliseconds (optional)

NAMESPACE="data-ingestion"
KAFKA_POD="kafka-0"
KAFKA_BROKER="kafka-headless.data-ingestion.svc.cluster.local:9092"

if [ -z "$SOURCE_TOPIC" ] || [ -z "$TARGET_TOPIC" ]; then
  echo "Usage: $0 <source_topic> <target_topic> [start_timestamp] [end_timestamp]"
  echo ""
  echo "Examples:"
  echo "  Full replay:  $0 postgres.public.users postgres.public.users_replay"
  echo "  Time range:   $0 postgres.public.users postgres.public.users_replay 1704556800000 1704643200000"
  exit 1
fi

echo "=== Kafka Topic Replay ==="
echo "Source Topic: ${SOURCE_TOPIC}"
echo "Target Topic: ${TARGET_TOPIC}"
if [ -n "$START_TIMESTAMP" ]; then
  echo "Start Time: ${START_TIMESTAMP}"
  echo "End Time: ${END_TIMESTAMP}"
fi
echo ""

# Verify source topic exists
echo "Verifying source topic..."
if ! kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-topics --bootstrap-server ${KAFKA_BROKER} --list | grep -q "^${SOURCE_TOPIC}$"; then
  echo "ERROR: Source topic '${SOURCE_TOPIC}' not found"
  exit 1
fi

# Create target topic if it doesn't exist
echo "Creating target topic if needed..."
kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-topics --bootstrap-server ${KAFKA_BROKER} \
  --create --if-not-exists --topic ${TARGET_TOPIC} \
  --partitions 6 --replication-factor 3 \
  --config retention.ms=604800000 \
  --config compression.type=lz4 \
  --config cleanup.policy=delete

# Get message count from source topic
echo "Counting messages in source topic..."
MESSAGE_COUNT=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list ${KAFKA_BROKER} \
  --topic ${SOURCE_TOPIC} | \
  awk -F':' '{sum += $3} END {print sum}')

echo "Source topic contains ${MESSAGE_COUNT} messages"
echo ""

# Perform replay
if [ -n "$START_TIMESTAMP" ]; then
  echo "Replaying messages from time range..."
  
  # Create temporary file for filtered messages
  TEMP_FILE="/tmp/kafka_replay_${TIMESTAMP}.txt"
  
  # Consume with timestamp filter
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${SOURCE_TOPIC} \
    --property print.timestamp=true \
    --property print.key=true \
    --property print.value=true \
    --from-beginning \
    --timeout-ms 60000 > ${TEMP_FILE} 2>/dev/null || true
  
  # Filter by timestamp and produce to target
  awk -v start=${START_TIMESTAMP} -v end=${END_TIMESTAMP} \
    'BEGIN {FS="\t"} $1 >= start && $1 <= end {print $2"\t"$3}' ${TEMP_FILE} | \
    kubectl exec -i -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-console-producer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${TARGET_TOPIC} \
    --property parse.key=true \
    --property key.separator=$'\t' 2>/dev/null || true
  
  rm -f ${TEMP_FILE}
else
  echo "Replaying all messages..."
  
  # Full replay
  kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-console-consumer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${SOURCE_TOPIC} \
    --property print.key=true \
    --property print.value=true \
    --from-beginning \
    --timeout-ms 60000 2>/dev/null | \
    kubectl exec -i -n ${NAMESPACE} ${KAFKA_POD} -- \
    kafka-console-producer \
    --bootstrap-server ${KAFKA_BROKER} \
    --topic ${TARGET_TOPIC} \
    --property parse.key=true \
    --property key.separator=$'\t' 2>/dev/null || true
fi

# Verify replay
echo ""
echo "Verifying replay..."
TARGET_COUNT=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
  kafka-run-class kafka.tools.GetOffsetShell \
  --broker-list ${KAFKA_BROKER} \
  --topic ${TARGET_TOPIC} | \
  awk -F':' '{sum += $3} END {print sum}')

echo "Target topic now contains ${TARGET_COUNT} messages"
echo ""
echo "=== Topic Replay Complete ==="
echo "Source: ${SOURCE_TOPIC} (${MESSAGE_COUNT} messages)"
echo "Target: ${TARGET_TOPIC} (${TARGET_COUNT} messages)"
