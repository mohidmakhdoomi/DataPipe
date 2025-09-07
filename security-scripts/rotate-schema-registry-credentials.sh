#!/bin/bash
# rotate-schema-registry-credentials.sh
# Rotates Schema Registry authentication credentials

set -e

NAMESPACE="data-ingestion"
SECRET_NAME="schema-registry-auth"

echo "=== Schema Registry Credential Rotation ==="
echo "Namespace: $NAMESPACE"
echo "Secret: $SECRET_NAME"

# Generate new secure passwords
ADMIN_PASSWORD=$(openssl rand -base64 24)
PROBE_PASSWORD=$(openssl rand -base64 24)

echo "Generated new passwords for admin and probe users"

# Create temporary file for user-info
TEMP_FILE=$(mktemp)
cat > $TEMP_FILE <<EOF
admin:$ADMIN_PASSWORD,admin
probe:$PROBE_PASSWORD,readonly
EOF

echo "Created new user-info configuration"

# Update Kubernetes secret
echo "Updating Kubernetes secret..."
kubectl create secret generic $SECRET_NAME \
  --from-file=user-info=$TEMP_FILE \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --from-literal=probe-user=probe \
  --from-literal=probe-password="$PROBE_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - -n $NAMESPACE

# Clean up temp file
rm $TEMP_FILE

# Restart Schema Registry
echo "Restarting Schema Registry..."
kubectl rollout restart deployment schema-registry -n $NAMESPACE

# Wait for rollout to complete
echo "Waiting for Schema Registry rollout to complete..."
kubectl rollout status deployment schema-registry -n $NAMESPACE --timeout=300s

# Wait for service to stabilize
echo "Waiting for Schema Registry to stabilize..."
sleep 30

# Test new credentials
echo "Testing new admin credentials..."
SR_POD=$(kubectl get pods -n $NAMESPACE -l app=schema-registry -o jsonpath='{.items[0].metadata.name}')
if [ -n "$SR_POD" ]; then
    kubectl exec -n $NAMESPACE $SR_POD -- \
      curl -s -u admin:$ADMIN_PASSWORD http://localhost:8081/subjects
    echo "Admin credentials verified"
    
    kubectl exec -n $NAMESPACE $SR_POD -- \
      curl -s -u probe:$PROBE_PASSWORD http://localhost:8081/subjects
    echo "Probe credentials verified"
else
    echo "WARNING: Schema Registry pod not found for verification"
fi

# Update connector configurations with new credentials
echo "Updating Kafka Connect connectors with new Schema Registry credentials..."
CONNECT_POD=$(kubectl get pods -n $NAMESPACE -l app=kafka-connect -o jsonpath='{.items[0].metadata.name}')

if [ -n "$CONNECT_POD" ]; then
    # Update Debezium connector
    echo "Updating Debezium connector configuration..."
    kubectl exec -n $NAMESPACE $CONNECT_POD -- \
      curl -X PUT http://localhost:8083/connectors/postgres-cdc-connector/config \
      -H "Content-Type: application/json" \
      -d "{
        \"connector.class\": \"io.debezium.connector.postgresql.PostgresConnector\",
        \"tasks.max\": \"1\",
        \"database.hostname\": \"postgresql.data-ingestion.svc.cluster.local\",
        \"database.port\": \"5432\",
        \"database.user\": \"\${env:DBZ_DB_USERNAME}\",
        \"database.password\": \"\${env:DBZ_DB_PASSWORD}\",
        \"database.dbname\": \"ecommerce\",
        \"database.server.name\": \"postgres\",
        \"topic.prefix\": \"postgres\",
        \"table.include.list\": \"public.users,public.products,public.orders,public.order_items\",
        \"plugin.name\": \"pgoutput\",
        \"slot.name\": \"debezium_slot\",
        \"publication.name\": \"dbz_publication\",
        \"key.converter\": \"io.confluent.connect.avro.AvroConverter\",
        \"value.converter\": \"io.confluent.connect.avro.AvroConverter\",
        \"key.converter.schema.registry.url\": \"http://schema-registry.data-ingestion.svc.cluster.local:8081\",
        \"value.converter.schema.registry.url\": \"http://schema-registry.data-ingestion.svc.cluster.local:8081\",
        \"key.converter.basic.auth.credentials.source\": \"USER_INFO\",
        \"value.converter.basic.auth.credentials.source\": \"USER_INFO\",
        \"key.converter.basic.auth.user.info\": \"admin:$ADMIN_PASSWORD\",
        \"value.converter.basic.auth.user.info\": \"admin:$ADMIN_PASSWORD\",
        \"transforms\": \"unwrap\",
        \"transforms.unwrap.type\": \"io.debezium.transforms.ExtractNewRecordState\",
        \"transforms.unwrap.drop.tombstones\": \"true\",
        \"transforms.unwrap.delete.handling.mode\": \"rewrite\",
        \"transforms.unwrap.add.fields\": \"op,ts_ms,source.ts_ms,source.lsn\",
        \"snapshot.mode\": \"initial\",
        \"heartbeat.interval.ms\": \"30000\",
        \"heartbeat.topics.prefix\": \"__debezium-heartbeat\",
        \"provide.transaction.metadata\": \"true\",
        \"decimal.handling.mode\": \"string\",
        \"time.precision.mode\": \"adaptive_time_microseconds\",
        \"errors.tolerance\": \"all\",
        \"errors.log.enable\": \"true\",
        \"errors.log.include.messages\": \"true\",
        \"errors.deadletterqueue.topic.name\": \"connect-dlq\",
        \"errors.deadletterqueue.topic.replication.factor\": \"3\",
        \"errors.deadletterqueue.context.headers.enable\": \"true\",
        \"errors.retry.delay.max.ms\": \"60000\",
        \"errors.retry.timeout\": \"300000\"
      }"
    
    # Update S3 Sink connector
    echo "Updating S3 Sink connector configuration..."
    kubectl exec -n $NAMESPACE $CONNECT_POD -- \
      curl -X PUT http://localhost:8083/connectors/s3-sink-connector/config \
      -H "Content-Type: application/json" \
      -d "{
        \"connector.class\": \"io.confluent.connect.s3.S3SinkConnector\",
        \"tasks.max\": \"24\",
        \"topics.regex\": \"postgres\\\\.public\\\\..*\",
        \"s3.bucket.name\": \"\${env:S3_BUCKET_NAME}\",
        \"s3.region\": \"us-east-1\",
        \"s3.part.size\": \"5242880\",
        \"format.class\": \"io.confluent.connect.s3.format.parquet.ParquetFormat\",
        \"parquet.codec\": \"snappy\",
        \"parquet.block.size\": \"16777216\",
        \"parquet.page.size\": \"1048576\",
        \"partitioner.class\": \"io.confluent.connect.storage.partitioner.TimeBasedPartitioner\",
        \"partition.duration.ms\": \"3600000\",
        \"path.format\": \"'year'=YYYY/'month'=MM/'day'=dd/'hour'=HH\",
        \"locale\": \"en-US\",
        \"timezone\": \"UTC\",
        \"timestamp.extractor\": \"Record\",
        \"flush.size\": \"1000\",
        \"rotate.interval.ms\": \"60000\",
        \"key.converter\": \"io.confluent.connect.avro.AvroConverter\",
        \"value.converter\": \"io.confluent.connect.avro.AvroConverter\",
        \"key.converter.schema.registry.url\": \"http://schema-registry.data-ingestion.svc.cluster.local:8081\",
        \"value.converter.schema.registry.url\": \"http://schema-registry.data-ingestion.svc.cluster.local:8081\",
        \"key.converter.basic.auth.credentials.source\": \"USER_INFO\",
        \"value.converter.basic.auth.credentials.source\": \"USER_INFO\",
        \"key.converter.basic.auth.user.info\": \"admin:$ADMIN_PASSWORD\",
        \"value.converter.basic.auth.user.info\": \"admin:$ADMIN_PASSWORD\",
        \"consumer.override.max.poll.records\": \"1000\",
        \"consumer.override.max.poll.interval.ms\": \"180000\",
        \"consumer.override.fetch.max.bytes\": \"5242880\",
        \"errors.tolerance\": \"all\",
        \"errors.log.enable\": \"true\",
        \"errors.log.include.messages\": \"true\",
        \"errors.deadletterqueue.topic.name\": \"s3-sink-dlq\",
        \"errors.deadletterqueue.topic.replication.factor\": \"3\",
        \"errors.deadletterqueue.context.headers.enable\": \"true\",
        \"errors.retry.timeout\": \"0\",
        \"behavior.on.null.values\": \"ignore\",
        \"s3.retry.backoff.ms\": \"2000\",
        \"s3.retry.jitter.ms\": \"1000\",
        \"s3.max.retries\": \"7\",
        \"storage.class\": \"io.confluent.connect.s3.storage.S3Storage\"
      }"
    
    echo "Connector configurations updated"
else
    echo "WARNING: Kafka Connect pod not found for connector updates"
fi

echo "=== Schema Registry credential rotation completed successfully ==="
echo "New admin password: $ADMIN_PASSWORD"
echo "New probe password: $PROBE_PASSWORD"
echo "Please update any external clients with the new credentials"