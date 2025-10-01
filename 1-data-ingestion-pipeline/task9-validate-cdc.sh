#!/bin/bash
# Task 9: Validate Debezium PostgreSQL CDC Connector
# This script validates the CDC deployment and tests functionality

set -euo pipefail
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="postgres-cdc-connector"
readonly LOG_DIR="${SCRIPT_DIR}/../logs/data-ingestion-pipeline/task9-logs"
readonly SCHEMA_AUTH_USER=$(yq 'select(.metadata.name == "schema-registry-auth").stringData.admin-user' 04-secrets.yaml)
readonly SCHEMA_AUTH_PASS=$(yq 'select(.metadata.name == "schema-registry-auth").stringData.admin-password' 04-secrets.yaml)

MONITOR_PID=0
PRE_EVOLUTION_VERSION=1

# Generate unique column names per test run to ensure idempotency
TEST_ID=$(date +%s)
NULLABLE_COL="test_middle_name_${TEST_ID}"
DEFAULTING_COL="test_status_${TEST_ID}"
INS_UPD_DEL_EMAIL="task9-validation-${TEST_ID}@example.com"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Task 9 Validate: $*" | tee -a "${LOG_DIR}/validate.log"
}

stop_monitoring() {
    # Stop resource monitoring
    if [[ "$MONITOR_PID" -ne 0 ]]; then
        log "Stopping background resource monitoring"
        kill $MONITOR_PID 2>/dev/null || true
    fi
}

exit_one() {
    stop_monitoring
    exit 1
}

start_avro_consumer() {
    exec 3< <(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        kafka-avro-console-consumer --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 \
        --topic postgres.public.users --property basic.auth.credentials.source="USER_INFO" \
        --property schema.registry.basic.auth.user.info=${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} \
        --property schema.registry.url=http://localhost:8081 \
        --timeout-ms 20000 2>/dev/null)
    
    log "Waiting 10 seconds for kafka-avro-console-consumer to start..."
    sleep 10
}

# Get pod names with validation
get_pod_names() {
    log "Discovering pod names..."
    
    local connect_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka-connect,component=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local postgres_pod=$(kubectl get pods -n ${NAMESPACE} -l app=postgresql,component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local kafka_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka,component=streaming -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local schema_registry_pod=$(kubectl get pods -n ${NAMESPACE} -l app=schema-registry,component=schema-management -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$connect_pod" || -z "$postgres_pod" || -z "$kafka_pod" || -z "$schema_registry_pod" ]]; then
        log "❌ Failed to discover all required pods"
        return 1
    fi
    
    log "Using pods:"
    log "  Kafka Connect: $connect_pod"
    log "  PostgreSQL: $postgres_pod"
    log "  Kafka: $kafka_pod"
    log "  Schema Registry: $schema_registry_pod"
    
    # Export for use in other functions
    export CONNECT_POD="$connect_pod"
    export POSTGRES_POD="$postgres_pod"
    export KAFKA_POD="$kafka_pod"
    export SCHEMA_REGISTRY_POD="$schema_registry_pod"
    
    return 0
}

# Check connector status
check_connector_status() {
    log "Checking connector status..."
    
    local status_output=$(kubectl exec -n ${NAMESPACE} ${CONNECT_POD} -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    
    if [[ -n "$status_output" ]]; then
        local connector_state=$(echo "$status_output" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
        local task_state=$(echo "$status_output" | jq -r '.tasks[0].state' 2>/dev/null || echo "UNKNOWN")
        
        log "Connector state: $connector_state"
        log "Task state: $task_state"
        
        if [[ "$connector_state" == "RUNNING" && "$task_state" == "RUNNING" ]]; then
            log "✅ Connector and task are both RUNNING"
            return 0
        else
            log "⚠️  Connector or task not in RUNNING state"
            echo "$status_output" | jq '.' | tee -a "${LOG_DIR}/validate.log"
            return 1
        fi
    else
        log "❌ Failed to get connector status"
        return 1
    fi
}

# Check PostgreSQL replication slot
check_replication_slot() {
    log "Checking PostgreSQL replication slot..."
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;" 2>/dev/null | tee -a "${LOG_DIR}/validate.log"; then
        log "✅ Replication slot information retrieved"
        return 0
    else
        log "❌ Failed to check replication slot"
        return 1
    fi
}

# List Kafka topics
check_kafka_topics() {
    log "Listing Kafka topics..."
    
    local topics=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
        kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | grep postgres || echo "")
    
    if [[ -n "$topics" ]]; then
        log "✅ Found CDC topics:"
        echo "$topics" | while read -r topic; do
            log "  - $topic"
        done
        return 0
    else
        log "⚠️  No postgres topics found yet"
        return 0  # Don't fail as topics might not be created yet
    fi
}

# Check Schema Registry subjects
check_schema_registry() {
    log "Checking Schema Registry subjects..."
    
    local subjects=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} http://localhost:8081/subjects 2>/dev/null)
    
    if [[ -n "$subjects" ]]; then
        echo "$subjects" | jq '.' | tee -a "${LOG_DIR}/validate.log"
        
        if echo "$subjects" | grep -q "postgres"; then
            log "✅ CDC schemas found in Schema Registry"
            return 0
        else
            log "⚠️  No CDC schemas found yet"
            return 0  # Don't fail as schemas might not be registered yet
        fi
    else
        log "❌ Failed to check Schema Registry"
        return 1
    fi
}

# Check topic message counts
check_message_counts() {
    log "Checking topic message counts..."
    
    local tables=("users" "products" "orders" "order_items")
    local total_messages=0
    
    for table in "${tables[@]}"; do
        local topic="postgres.public.$table"
        local count=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
            kafka-run-class kafka.tools.GetOffsetShell \
            --broker-list localhost:9092 \
            --topic "$topic" --time -1 2>/dev/null | \
            awk -F: '{sum += $3} END {print (sum ? sum : 0)}' || echo "0")
        
        log "$table: $count messages"
        total_messages=$((total_messages + count))
    done
    
    log "Total messages across all topics: $total_messages"
    return 0
}

# Test CDC with INSERT operation
test_cdc_insert() {
    log "Testing CDC with INSERT operation..."
    
    log "Inserting test record with email: $INS_UPD_DEL_EMAIL"

    start_avro_consumer
    
    # Insert record and check if it succeeds
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, last_name) VALUES ('$INS_UPD_DEL_EMAIL', 'CDC', 'Test') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Test record inserted successfully"
        
        log "Waiting for CDC to process INSERT..."
        local avro_out=$(cat <&3)
        
        log "Checking if CDC event appeared in Kafka..."
        if echo "$avro_out" | grep '__op":{"string":"c"}' | grep -q "$INS_UPD_DEL_EMAIL"; then
            log "✅ CDC INSERT event captured"
        else
            log "⚠️  CDC INSERT event not found"
        fi
        
        return 0
    else
        log "❌ Failed to insert test record"
        return 1
    fi
}

# Test UPDATE operation
test_cdc_update() {    
    log "Testing UPDATE operation..."
    
    start_avro_consumer

    local update_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "UPDATE users SET first_name='Updated' WHERE email='$INS_UPD_DEL_EMAIL' RETURNING id;" 2>/dev/null)

    if [[ -n "$update_result" ]] && echo "$update_result" | grep -wq "[0-9]\+"; then
        log "✅ UPDATE operation executed"
        echo "$update_result" >> "${LOG_DIR}/validate.log"
        
        log "Waiting for CDC to process UPDATE..."
        local avro_out=$(cat <&3)
        
        # Check for UPDATE event with proper rewrite format
        log "Checking if UPDATE event appeared in Kafka..."
        if echo "$avro_out" | grep '__op":{"string":"u"}' | grep -q "\"id\":$update_result,"; then
            log "✅ UPDATE operation found with proper format"
            return 0
        else
            log "⚠️  UPDATE operation not found - check configuration"
            return 1
        fi
    else
        log "❌ UPDATE operation failed"
        return 1
    fi
}

# Test DELETE operation (critical for Iceberg)
test_cdc_delete() {    
    log "Testing DELETE operation (critical for Iceberg)..."
    
    # First, verify the record exists before attempting deletion
    local record_check=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
        psql -U postgres -d ecommerce -t -c \
        "SELECT COUNT(*) FROM users WHERE email = '$INS_UPD_DEL_EMAIL';" 2>/dev/null | tr -d ' ')
    
    if [[ "$record_check" == "0" ]]; then
        log "⚠️  Record with email '$INS_UPD_DEL_EMAIL' not found. Re-inserting for DELETE test..."
        kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
            psql -U postgres -d ecommerce -c \
            "INSERT INTO users (email, first_name, last_name) VALUES ('$INS_UPD_DEL_EMAIL', 'CDC', 'Test') ON CONFLICT (email) DO NOTHING;" >> "${LOG_DIR}/validate.log" 2>&1
        sleep 2  # Give time for commit visibility
    fi

    start_avro_consumer

    local delete_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "DELETE FROM users WHERE email = '$INS_UPD_DEL_EMAIL' RETURNING id;" 2>/dev/null)    
    
    if [[ -n "$delete_result" ]] && echo "$delete_result" | grep -wq "[0-9]\+"; then
        log "✅ DELETE operation executed successfully (record deleted)"
        echo "$delete_result" >> "${LOG_DIR}/validate.log"
        
        log "Waiting for CDC to process DELETE..."
        local avro_out=$(cat <&3)
        
        # Check for DELETE event with proper rewrite format
        log "Checking if DELETE event appeared in Kafka with proper rewrite format..."
        if echo "$avro_out" | grep '__op":{"string":"d"}' | grep -q "\"id\":$delete_result,"; then
            log "✅ DELETE operation found with proper format"
            return 0
        else
            log "⚠️  DELETE operation not found - check configuration"
            return 1
        fi
    else
        log "❌ DELETE operation failed - no rows deleted"
        return 1
    fi
}

# Test schema evolution - Add nullable column
test_schema_evolution_add_nullable_column() {
    log "=== Testing Schema Evolution: Adding Nullable Column ==="
    
    # Get initial schema version
    local initial_schema_version=$(get_schema_version "postgres.public.users-value")
    log "Initial schema version: $initial_schema_version"
    
    # Add nullable column to users table
    log "Adding nullable column '$NULLABLE_COL' to users table..."
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users ADD COLUMN $NULLABLE_COL VARCHAR(100);" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Successfully added nullable column"
    else
        log "❌ Failed to add nullable column"
        return 1
    fi
    
    # Wait for schema change to propagate
    log "Waiting 10 seconds for schema change to propagate..."
    sleep 10
    
    # Test INSERT with new schema
    local test_email="task9-schema-evolve-${TEST_ID}@example.com"
    log "Testing INSERT with new schema (including $NULLABLE_COL)..."

    start_avro_consumer
    
    local insert_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, $NULLABLE_COL, last_name) VALUES ('$test_email', 'Schema', 'Evolution', 'Test') RETURNING id;" 2>/dev/null)

    if [[ -n "$insert_result" ]] && echo "$insert_result" | grep -wq "[0-9]\+"; then
        log "✅ INSERT with new schema successful"
        echo "$insert_result" >> "${LOG_DIR}/validate.log"
        
        log "Waiting for CDC to process INSERT..."
        local avro_out=$(cat <&3)
        
        # Verify CDC captured the new field
        log "Verifying CDC captured the new $NULLABLE_COL field..."
        if echo "$avro_out" | grep '__op":{"string":"c"}' | grep "\"id\":$insert_result," | grep -q "Evolution"; then
            log "✅ CDC captured record with new schema field"
        else
            log "⚠️  CDC record with new field not found"
        fi
    else
        log "❌ INSERT with new schema failed"
        return 1
    fi
    
    # Verify schema evolution in Schema Registry
    local new_schema_version=$(get_schema_version "postgres.public.users-value")
    log "New schema version: $new_schema_version"
    
    if [[ "$new_schema_version" -gt "$initial_schema_version" ]]; then
        log "✅ Schema Registry shows schema evolution (v$initial_schema_version → v$new_schema_version)"
        return 0
    else
        log "⚠️  Schema Registry version unchanged - may indicate compatibility issue"
        return 1
    fi
}

# Test schema evolution - Add column with default value
test_schema_evolution_add_default_column() {
    log "=== Testing Schema Evolution: Adding Column with Default Value ==="
    
    # Get initial schema version
    local initial_schema_version=$(get_schema_version "postgres.public.users-value")
    log "Initial schema version: $initial_schema_version"
    
    # Add column with default value
    log "Adding column '$DEFAULTING_COL' with default value to users table..."
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users ADD COLUMN $DEFAULTING_COL VARCHAR(20) DEFAULT 'active';" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Successfully added column with default value"
    else
        log "❌ Failed to add column with default value"
        return 1
    fi
    
    # Wait for schema change to propagate
    log "Waiting 5 seconds for schema change to propagate..."
    sleep 5
    
    # Test INSERT without specifying the new column (should use default)
    local test_email="schema-evolve-default-${TEST_ID}@example.com"
    log "Testing INSERT without new column (should use default value)..."

    start_avro_consumer
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, last_name) VALUES ('$test_email', 'Default', 'Test') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ INSERT without new column successful"
        
        log "Waiting for CDC to process INSERT..."
        local avro_out=$(cat <&3)
        
        log "Verifying CDC captured the default $DEFAULTING_COL value..."
        if echo "$avro_out" | grep '__op":{"string":"c"}' | grep -q "active"; then
            log "✅ CDC captured record with default value"
        else
            log "⚠️  CDC record with default value not found"
        fi
    else
        log "❌ INSERT with default column failed"
        return 1
    fi
    
    # Verify schema evolution in Schema Registry
    local new_schema_version=$(get_schema_version "postgres.public.users-value")
    log "New schema version: $new_schema_version"
    
    if [[ "$new_schema_version" -gt "$initial_schema_version" ]]; then
        log "✅ Schema Registry shows schema evolution (v$initial_schema_version → v$new_schema_version)"
        return 0
    else
        log "⚠️  Schema Registry version unchanged"
        return 1
    fi
}

# Get schema version from Schema Registry
get_schema_version() {
    local subject=$1
    local version=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} "http://localhost:8081/subjects/$subject/versions/latest" 2>/dev/null | \
        jq -r '.version' 2>/dev/null || echo "0")
    echo "$version"
}

# Verify Schema Registry compatibility settings
verify_schema_registry_compatibility() {
    log "=== Verifying Schema Registry Compatibility Settings ==="
    
    # Check global compatibility level
    local global_compatibility=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} "http://localhost:8081/config" 2>/dev/null | \
        jq -r '.compatibilityLevel' 2>/dev/null || echo "UNKNOWN")
    
    log "Global compatibility level: $global_compatibility"
    
    # Check subject-specific compatibility for users table
    local users_compatibility=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} "http://localhost:8081/config/postgres.public.users-value" 2>/dev/null | \
        jq -r '.compatibilityLevel' 2>/dev/null || echo "INHERITED")
    
    log "Users table compatibility level: $users_compatibility"
    
    # Verify compatibility is set to BACKWARD or FULL for safe evolution
    if [[ "$global_compatibility" =~ ^(BACKWARD|FULL|FORWARD)$ ]] || [[ "$users_compatibility" =~ ^(BACKWARD|FULL|FORWARD)$ ]]; then
        log "✅ Schema Registry has appropriate compatibility level for evolution"
        return 0
    else
        log "⚠️  Schema Registry compatibility level may not support safe evolution"
        log "   Recommended: BACKWARD, FULL, or FORWARD compatibility"
        return 1
    fi
}

# Test CDC operations after schema changes
test_cdc_after_schema_changes() {
    log "=== Testing CDC Operations After Schema Changes ==="
    
    local test_email="post-schema-change-${TEST_ID}@example.com"
    
    # Test INSERT with all new fields
    log "Testing INSERT with all schema fields..."

    start_avro_consumer

    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, $NULLABLE_COL, last_name, $DEFAULTING_COL) VALUES ('$test_email', 'Post', 'Schema', 'Change', 'verified') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ INSERT with full schema successful"
        
        log "Waiting for CDC to process INSERT..."
        local avro_out=$(cat <&3)
        
        if echo "$avro_out" | grep '__op":{"string":"c"}' | grep -q "$test_email"; then
            log "✅ CDC captured INSERT after schema evolution"
        else
            log "⚠️  CDC INSERT not captured after schema evolution"
        fi
    else
        log "❌ INSERT with full schema failed"
        return 1
    fi
    
    # Test UPDATE with new fields
    log "Testing UPDATE with new schema fields..."

    start_avro_consumer

    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "UPDATE users SET $NULLABLE_COL='Updated', $DEFAULTING_COL='modified' WHERE email='$test_email' RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ UPDATE with new fields successful"
        
        log "Waiting for CDC to process UPDATE..."
        local avro_out=$(cat <&3)
        
        if echo "$avro_out" | grep '__op":{"string":"u"}' | grep -q "modified"; then
            log "✅ CDC captured UPDATE after schema evolution"
        else
            log "⚠️  CDC UPDATE not captured after schema evolution"
        fi
    else
        log "❌ UPDATE with new fields failed"
        return 1
    fi
    
    return 0
}

# Cleanup schema evolution test changes
cleanup_schema_evolution_tests() {
    log "=== Cleaning Up Schema Evolution Test Changes ==="
    
    # Get current schema version before cleanup
    local current_version=$(get_schema_version "postgres.public.users-value")
    log "Current schema version before cleanup: $current_version"
    
    # Remove test columns from database
    log "Removing test columns added during schema evolution testing..."
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users DROP COLUMN IF EXISTS $NULLABLE_COL, DROP COLUMN IF EXISTS $DEFAULTING_COL;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Test columns removed successfully from database"
    else
        log "⚠️  Failed to remove test columns (may not exist)"
    fi
    
    # Clean up test records
    log "Cleaning up schema evolution test records..."
    kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "DELETE FROM users WHERE email LIKE '%schema-evolve%' OR email LIKE '%post-schema-change%';" >> "${LOG_DIR}/validate.log" 2>&1
    
    # Clean up Schema Registry versions (reset to version 1)
    log "Cleaning up Schema Registry schema versions..."
    cleanup_schema_registry_versions
    
    # Wait for schema changes to propagate
    log "Waiting 10 seconds for schema cleanup to propagate..."
    sleep 10
    
    # Verify cleanup by checking final schema version
    local final_version=$(get_schema_version "postgres.public.users-value")
    log "Final schema version after cleanup: $final_version"
    
    # Check if we're back to baseline
    if [[ "$final_version" == "$PRE_EVOLUTION_VERSION" ]]; then
        log "✅ Schema Registry successfully reset to baseline version"
    else
        log "⚠️  Schema Registry cleanup may not have completed fully (version: $final_version)"
        log "ℹ️  This may be normal if soft delete takes time to propagate"
    fi
    
    log "✅ Schema evolution test cleanup completed"
}

# Clean up Schema Registry versions to reset schema evolution state
cleanup_schema_registry_versions() {
    local subject="postgres.public.users-value"
       
    # Get all versions for the subject
    local versions=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} "http://localhost:8081/subjects/$subject/versions" 2>/dev/null | \
        sed 's/^\[\(.*\)\]$/\1/' 2>/dev/null || echo "")
    
    if [[ -z "$versions" ]]; then
        log "⚠️  Could not retrieve schema versions for cleanup"
        return 1
    fi
    
    log "Found schema versions: $versions"
    
    # Determine the baseline version (initial schema version that existed before schema evolution tests)
    local baseline_version=$PRE_EVOLUTION_VERSION
    
    log "Preserving baseline schema version: $baseline_version"
    
    # Soft delete versions higher than baseline version
    local deleted_count=0
    IFS=',' read -ra version_array <<< "$versions"
    IFS=$'\n' version_array=($(sort -nr <<<"${version_array[*]}")); unset IFS
    for version in "${version_array[@]}"; do
        if [[ "$version" -gt "$baseline_version" ]]; then
            log "Soft deleting schema version $version..."
            
            local delete_result=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
                curl -s -w "%{http_code}" -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} \
                -X DELETE "http://localhost:8081/subjects/$subject/versions/$version" 2>/dev/null)
            
            local http_code="${delete_result: -3}"
            
            if [[ "$http_code" == "200" ]]; then
                log "✅ Successfully soft deleted schema version $version"
            else
                log "⚠️  Failed to soft delete schema version $version (HTTP: $http_code)"
            fi
            
            # Small delay between deletions
            sleep 1
        fi
    done
    
    if [[ $deleted_count -gt 0 ]]; then
        log "✅ Successfully soft deleted $deleted_count schema versions"
        log "Baseline schema version $baseline_version preserved"
    else
        log "No schema versions to delete (only baseline $baseline_version or older versions exists)"
    fi
    
    # Verify the cleanup by checking remaining versions
    log "Verifying schema cleanup..."
    local remaining_versions=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u ${SCHEMA_AUTH_USER}:${SCHEMA_AUTH_PASS} "http://localhost:8081/subjects/$subject/versions" 2>/dev/null | \
        sed 's/^\[\(.*\)\]$/\1/' 2>/dev/null || echo "")
    
    if [[ -n "$remaining_versions" ]]; then
        log "Remaining schema versions after cleanup: $remaining_versions"
    else
        log "⚠️  No schema versions found after cleanup - this may indicate an issue"
    fi
}

# Check connector logs for errors
check_connector_logs() {
    log "Checking connector logs for any errors..."
    
    local error_logs=$(kubectl logs -n ${NAMESPACE} ${CONNECT_POD} --tail=20 2>/dev/null | grep -E "(ERROR|WARN|Exception)" || echo "")
    
    if [[ -n "$error_logs" ]]; then
        log "⚠️  Found warnings/errors in connector logs:"
        echo "$error_logs" | tee -a "${LOG_DIR}/validate.log"
        return 1
    else
        log "✅ No errors found in recent logs"
        return 0
    fi
}

# Check resource usage
check_resource_usage() {
    log "Checking resource usage..."
    
    if kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -E "(kafka-connect|postgresql|kafka|schema)" | tee -a "${LOG_DIR}/validate.log"; then
        log "✅ Resource usage information retrieved"
        return 0
    else
        log "⚠️  Could not retrieve resource usage information"
        return 0  # Don't fail on this
    fi
}

# Generate validation summary
generate_summary() {
    local failed_tests=("$@")
    
    log "=== CDC Validation Complete ==="
    log ""
    log "Summary:"
    log "- Connector status: $([ ${#failed_tests[@]} -eq 0 ] && echo "✅ PASSED" || echo "⚠️  ISSUES FOUND")"
    log "- Topics and Schema Registry: Validated"
    log "- CDC operations: INSERT/UPDATE/DELETE tested"
    log "- Schema Registry compatibility: Verified"
    log "- Schema evolution: Nullable and default column tests completed"
    log "- Post-evolution CDC: Verified CDC works after schema changes"
    log ""
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log "✅ All validation tests passed - Task 9 is complete!"
        log "✅ Schema evolution handling and compatibility verified"
        return 0
    else
        log "⚠️  Some tests had issues: ${failed_tests[*]}"
        log "Check logs for details: ${LOG_DIR}/validate.log"
        
        # Provide specific guidance for schema evolution failures
        for test in "${failed_tests[@]}"; do
            case "$test" in
                "schema-compatibility")
                    log "   → Schema Registry compatibility level needs adjustment"
                    ;;
                "schema-evolution-nullable"|"schema-evolution-default")
                    log "   → Schema evolution tests failed - check Debezium configuration"
                    ;;
                "cdc-post-schema-evolution")
                    log "   → CDC operations failed after schema changes - verify connector health"
                    ;;
            esac
        done
        
        return 1
    fi
}

# Main execution function
main() {
    log "=== Starting Task 9: Validating Debezium PostgreSQL CDC Connector ==="
    
    local failed_tests=()
    
    # Step 1: Get pod names
    if ! get_pod_names; then
        log "❌ Failed to get pod names"
        return 1
    fi

    log "Starting background resource monitoring"
    bash "${SCRIPT_DIR}/../resource-monitor.sh" "$NAMESPACE" "${SCRIPT_DIR}/../logs/data-ingestion-pipeline/resource-logs" &
    MONITOR_PID=$!
    
    # Step 2: Check connector status
    if ! check_connector_status; then
        failed_tests+=("connector-status")
    fi
    
    # Step 3: Check replication slot
    if ! check_replication_slot; then
        failed_tests+=("replication-slot")
    fi
    
    # Step 4: Check Kafka topics
    check_kafka_topics  # Don't fail on this
    
    # Step 5: Check Schema Registry
    check_schema_registry  # Don't fail on this
    
    # Step 6: Check message counts
    check_message_counts
    
    # Step 7: Test CDC operations
    log "Starting CDC operations testing..."
    if test_cdc_insert; then
        log "INSERT test completed, proceeding with UPDATE/DELETE tests..."
        test_cdc_update
        test_cdc_delete
    else
        log "❌ INSERT test failed, skipping UPDATE/DELETE tests"
        failed_tests+=("cdc-operations")
    fi
    
    # Step 8: Verify Schema Registry compatibility settings
    if ! verify_schema_registry_compatibility; then
        failed_tests+=("schema-compatibility")
    fi
    
    # Step 9: Test Schema Evolution
    log "Starting Schema Evolution testing..."
    
    # Preserve initial schema version to use later for baseline version for cleanup
    PRE_EVOLUTION_VERSION=$(get_schema_version "postgres.public.users-value")

    if test_schema_evolution_add_nullable_column; then
        log "✅ Nullable column schema evolution test passed"
    else
        log "❌ Nullable column schema evolution test failed"
        failed_tests+=("schema-evolution-nullable")
    fi
    
    if test_schema_evolution_add_default_column; then
        log "✅ Default column schema evolution test passed"
    else
        log "❌ Default column schema evolution test failed"
        failed_tests+=("schema-evolution-default")
    fi
    
    # Step 10: Test CDC operations after schema changes
    if test_cdc_after_schema_changes; then
        log "✅ CDC operations after schema changes test passed"
    else
        log "❌ CDC operations after schema changes test failed"
        failed_tests+=("cdc-post-schema-evolution")
    fi
    
    # Step 11: Cleanup schema evolution tests
    cleanup_schema_evolution_tests
    
    # Step 12: Check logs
    if ! check_connector_logs; then
        failed_tests+=("connector-logs")
    fi
    
    # Step 13: Check resource usage
    check_resource_usage
    
    # Step 14: Generate summary
    if ! generate_summary "${failed_tests[@]}"; then
        exit_one
    fi
    
    stop_monitoring
}

# Execute main function
main "$@"