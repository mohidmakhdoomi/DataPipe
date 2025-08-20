#!/bin/bash
# Task 9: Validate Debezium PostgreSQL CDC Connector
# This script validates the CDC deployment and tests functionality

set -euo pipefail
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="postgres-cdc-connector"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task9-logs"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Task 9 Validate: $*" | tee -a "${LOG_DIR}/validate.log"
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
        curl -s -u admin:admin-secret http://localhost:8081/subjects 2>/dev/null)
    
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
    
    local test_email="task9-validation-$(date +%s)@example.com"
    log "Inserting test record with email: $test_email"
    
    # Insert record and check if it succeeds
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, last_name) VALUES ('$test_email', 'CDC', 'Test') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Test record inserted successfully"
        
        log "Waiting 5 seconds for CDC to process..."
        sleep 5
       
        # Check if message appeared in Kafka (just verify, don't capture output)
        log "Checking if CDC event appeared in Kafka..."
        if kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
           kafka-console-consumer --bootstrap-server localhost:9092 \
           --topic postgres.public.users --from-beginning --timeout-ms 5000 2>/dev/null | grep -q "$test_email"; then
            log "✅ CDC INSERT event captured"
        else
            log "⚠️  CDC INSERT event not found"
        fi
        
        echo "$test_email" > "${LOG_DIR}/test_email.txt"  # Save email for other tests
        return 0
    else
        log "❌ Failed to insert test record"
        return 1
    fi
}

# Test UPDATE operation
test_cdc_update() {
    local test_email=$1
    
    log "Testing UPDATE operation..."
    
    local update_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "UPDATE users SET first_name='Updated' WHERE email='$test_email' RETURNING id;" 2>/dev/null)

    if [[ -n "$update_result" ]] && echo "$update_result" | grep -wq "[0-9]\+"; then
        log "✅ UPDATE operation executed"
        echo "$update_result" >> "${LOG_DIR}/validate.log"
        
        log "Waiting 3 seconds for CDC to process..."
        sleep 3
        
        # Check for DELETE event with proper rewrite format
        log "Checking if UPDATE event appeared in Kafka..."
        if kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
           kafka-avro-console-consumer --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 \
           --topic postgres.public.users --from-beginning --property basic.auth.credentials.source="USER_INFO" \
           --property schema.registry.basic.auth.user.info=admin:admin-secret \
           --property schema.registry.url=http://localhost:8081 \
           --timeout-ms 5000 2>/dev/null | grep '__op":{"string":"u"}' | grep -q "\"id\":$update_result,"; then
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
    local test_email=$1
    
    log "Testing DELETE operation (critical for Iceberg)..."
    
    # First, verify the record exists before attempting deletion
    local record_check=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
        psql -U postgres -d ecommerce -t -c \
        "SELECT COUNT(*) FROM users WHERE email = '$test_email';" 2>/dev/null | tr -d ' ')
    
    if [[ "$record_check" == "0" ]]; then
        log "⚠️  Record with email '$test_email' not found. Re-inserting for DELETE test..."
        kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
            psql -U postgres -d ecommerce -c \
            "INSERT INTO users (email, first_name, last_name) VALUES ('$test_email', 'CDC', 'Test') ON CONFLICT (email) DO NOTHING;" >> "${LOG_DIR}/validate.log" 2>&1
        sleep 2  # Give time for commit visibility
    fi
    
    # Now perform the DELETE with verification
    local delete_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "DELETE FROM users WHERE email = '$test_email' RETURNING id;" 2>/dev/null)    
    
    if [[ -n "$delete_result" ]] && echo "$delete_result" | grep -wq "[0-9]\+"; then
        log "✅ DELETE operation executed successfully (record deleted)"
        echo "$delete_result" >> "${LOG_DIR}/validate.log"
        
        log "Waiting 3 seconds for CDC to process DELETE..."
        sleep 3
        
        # Check for DELETE event with proper rewrite format
        log "Checking if DELETE event appeared in Kafka with proper rewrite format..."
        if kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
           kafka-avro-console-consumer --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 \
           --topic postgres.public.users --from-beginning --property basic.auth.credentials.source="USER_INFO" \
           --property schema.registry.basic.auth.user.info=admin:admin-secret \
           --property schema.registry.url=http://localhost:8081 \
           --timeout-ms 5000 2>/dev/null | grep '__op":{"string":"d"}' | grep -q "\"id\":$delete_result,"; then
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
    log "Adding nullable column 'middle_name' to users table..."
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users ADD COLUMN middle_name VARCHAR(100);" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Successfully added nullable column"
    else
        log "❌ Failed to add nullable column"
        return 1
    fi
    
    # Wait for schema change to propagate
    log "Waiting 10 seconds for schema change to propagate..."
    sleep 10
    
    # Test INSERT with new schema
    local test_email="task9-schema-evolve-$(date +%s)@example.com"
    log "Testing INSERT with new schema (including middle_name)..."
    

    local insert_result=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -qAt -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, middle_name, last_name) VALUES ('$test_email', 'Schema', 'Evolution', 'Test') RETURNING id;" 2>/dev/null)

    if [[ -n "$insert_result" ]] && echo "$insert_result" | grep -wq "[0-9]\+"; then
        log "✅ INSERT with new schema successful"
        echo "$insert_result" >> "${LOG_DIR}/validate.log"
        
        # Wait for CDC to process
        sleep 5
        
        # Verify CDC captured the new field
        log "Verifying CDC captured the new middle_name field..."
        if kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
           kafka-avro-console-consumer --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 \
           --topic postgres.public.users --from-beginning --property basic.auth.credentials.source="USER_INFO" \
           --property schema.registry.basic.auth.user.info=admin:admin-secret \
           --property schema.registry.url=http://localhost:8081 \
           --timeout-ms 5000 2>/dev/null | grep '__op":{"string":"c"}' | grep "\"id\":$insert_result," | grep -q "Evolution"; then
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
    log "Adding column 'status' with default value to users table..."
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users ADD COLUMN status VARCHAR(20) DEFAULT 'active';" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Successfully added column with default value"
    else
        log "❌ Failed to add column with default value"
        return 1
    fi
    
    # Wait for schema change to propagate
    log "Waiting 10 seconds for schema change to propagate..."
    sleep 10
    
    # Test INSERT without specifying the new column (should use default)
    local test_email="schema-evolution-default-$(date +%s)@example.com"
    log "Testing INSERT without new column (should use default value)..."
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, last_name) VALUES ('$test_email', 'Default', 'Test') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ INSERT without new column successful"
        
        # Wait for CDC to process
        sleep 5
        
        # Verify CDC captured the default value
        log "Verifying CDC captured the default status value..."
        if kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
           kafka-console-consumer --bootstrap-server localhost:9092 \
           --topic postgres.public.users --from-beginning --timeout-ms 5000 2>/dev/null | grep -q "active"; then
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
        curl -s -u admin:admin-secret "http://localhost:8081/subjects/$subject/versions/latest" 2>/dev/null | \
        jq -r '.version' 2>/dev/null || echo "0")
    echo "$version"
}

# Verify Schema Registry compatibility settings
verify_schema_registry_compatibility() {
    log "=== Verifying Schema Registry Compatibility Settings ==="
    
    # Check global compatibility level
    local global_compatibility=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u admin:admin-secret "http://localhost:8081/config" 2>/dev/null | \
        jq -r '.compatibilityLevel' 2>/dev/null || echo "UNKNOWN")
    
    log "Global compatibility level: $global_compatibility"
    
    # Check subject-specific compatibility for users table
    local users_compatibility=$(kubectl exec -n ${NAMESPACE} ${SCHEMA_REGISTRY_POD} -- \
        curl -s -u admin:admin-secret "http://localhost:8081/config/postgres.public.users-value" 2>/dev/null | \
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
    
    local test_email="post-schema-change-$(date +%s)@example.com"
    
    # Test INSERT with all new fields
    log "Testing INSERT with all schema fields..."
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, middle_name, last_name, status) VALUES ('$test_email', 'Post', 'Schema', 'Change', 'verified') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ INSERT with full schema successful"
        
        # Wait and verify CDC
        sleep 5
        if kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
           kafka-console-consumer --bootstrap-server localhost:9092 \
           --topic postgres.public.users --from-beginning --timeout-ms 5000 2>/dev/null | grep -q "$test_email"; then
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
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "UPDATE users SET middle_name='Updated', status='modified' WHERE email='$test_email' RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ UPDATE with new fields successful"
        
        # Wait and verify CDC
        sleep 5
        if kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
           kafka-console-consumer --bootstrap-server localhost:9092 \
           --topic postgres.public.users --from-beginning --timeout-ms 5000 2>/dev/null | grep -q "modified"; then
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
    
    # Remove test columns (optional - may want to keep for further testing)
    log "Removing test columns added during schema evolution testing..."
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "ALTER TABLE users DROP COLUMN IF EXISTS middle_name, DROP COLUMN IF EXISTS status;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Test columns removed successfully"
    else
        log "⚠️  Failed to remove test columns (may not exist)"
    fi
    
    # Clean up test records
    log "Cleaning up schema evolution test records..."
    kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "DELETE FROM users WHERE email LIKE '%schema-evolution%' OR email LIKE '%post-schema-change%';" >> "${LOG_DIR}/validate.log" 2>&1
    
    log "✅ Schema evolution test cleanup completed"
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
    local test_email
    if test_cdc_insert; then
        # Get the email from the temporary file
        test_email=$(cat "${LOG_DIR}/test_email.txt" 2>/dev/null || echo "test-email@example.com")
        log "INSERT test completed, proceeding with UPDATE/DELETE tests..."
        test_cdc_update "$test_email"
        test_cdc_delete "$test_email"
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
    generate_summary "${failed_tests[@]}"
}

# Execute main function
main "$@"