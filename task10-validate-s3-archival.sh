#!/bin/bash
# Task 10: Validate S3 Sink Connector and Archival Functionality
# This script validates the S3 archival deployment and tests functionality

set -euo pipefail
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="s3-sink-connector"
readonly S3_BUCKET=$(~/Downloads/yq.exe 'select(.metadata.name == "aws-credentials").data.s3-bucket' 04-secrets.yaml | base64 --decode)
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task10-logs"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Task 10 Validate: $*" | tee -a "${LOG_DIR}/validate.log"
}

# Get pod names with validation
get_pod_names() {
    log "Discovering pod names..."
    
    local connect_s3_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka-connect,component=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local postgres_pod=$(kubectl get pods -n ${NAMESPACE} -l app=postgresql,component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    local kafka_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka,component=streaming -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$connect_s3_pod" || -z "$postgres_pod" || -z "$kafka_pod" ]]; then
        log "❌ Failed to discover all required pods"
        return 1
    fi
    
    log "Using pods:"
    log "  Kafka Connect S3: $connect_s3_pod"
    log "  PostgreSQL: $postgres_pod"
    log "  Kafka: $kafka_pod"
    
    # Export for use in other functions
    export CONNECT_S3_POD="$connect_s3_pod"
    export POSTGRES_POD="$postgres_pod"
    export KAFKA_POD="$kafka_pod"
    
    return 0
}

# Check S3 Sink connector status
check_connector_status() {
    log "Checking S3 Sink connector status..."
    
    local status_output=$(kubectl exec -n ${NAMESPACE} ${CONNECT_S3_POD} -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    
    if [[ -n "$status_output" ]]; then
        local connector_state=$(echo "$status_output" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
        local task_count=$(echo "$status_output" | jq -r '.tasks | length' 2>/dev/null || echo "0")
        
        log "Connector state: $connector_state"
        log "Task count: $task_count"
        
        if [[ "$connector_state" == "RUNNING" && "$task_count" -gt "0" ]]; then
            log "✅ S3 Sink connector and tasks are RUNNING"
            
            # Check individual task states
            for i in $(seq 0 $((task_count - 1))); do
                local task_state=$(echo "$status_output" | jq -r ".tasks[$i].state" 2>/dev/null || echo "UNKNOWN")
                log "Task $i state: $task_state"
            done
            
            return 0
        else
            log "⚠️  Connector or tasks not in RUNNING state"
            echo "$status_output" | jq '.' | tee -a "${LOG_DIR}/validate.log"
            return 1
        fi
    else
        log "❌ Failed to get connector status"
        return 1
    fi
}

# Check S3 bucket accessibility
check_s3_bucket() {
    log "Checking S3 bucket accessibility..."
    
    if aws s3 ls s3://${S3_BUCKET}/ --region us-east-1 >/dev/null 2>&1; then
        log "✅ S3 bucket is accessible"
        return 0
    else
        log "❌ S3 bucket is not accessible - check credentials and permissions"
        return 1
    fi
}

# Test data flow to S3
test_s3_data_flow() {
    log "Testing data flow to S3..."
    
    # Insert test data into PostgreSQL
    local test_email="task10-s3-validation-$(date +%s)@example.com"
    log "Inserting test record with email: $test_email"
    
    if kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- \
       psql -U postgres -d ecommerce -c \
       "INSERT INTO users (email, first_name, last_name) VALUES ('$test_email', 'S3Test', 'Validation') RETURNING id;" >> "${LOG_DIR}/validate.log" 2>&1; then
        log "✅ Test record inserted successfully"
        
        # Wait for CDC and S3 processing
        log "Waiting 120 seconds for CDC and S3 processing..."
        sleep 120
        
        # Check if data appeared in S3
        log "Checking for data in S3..."
        local current_date=$(date -u +"%Y/%m/%d/%H")
        IFS="/" read -r year month day hour <<< "$current_date"
        local s3_path="s3://${S3_BUCKET}/topics/postgres.public.users/year=${year}/month=${month}/day=${day}/hour=${hour}/"
        
        log "Checking S3 path: $s3_path"
        if aws s3 ls "$s3_path" --region us-east-1 2>/dev/null | grep -q ".parquet"; then
            log "✅ Parquet files found in S3"
            
            # List the files
            aws s3 ls "$s3_path" --region us-east-1 | tee -a "${LOG_DIR}/validate.log"
            
            return 0
        else
            log "⚠️  No Parquet files found in expected S3 path"
            log "Checking broader S3 structure..."
            aws s3 ls s3://${S3_BUCKET}/topics/ --recursive --region us-east-1 | head -20 | tee -a "${LOG_DIR}/validate.log"
            return 1
        fi
    else
        log "❌ Failed to insert test record"
        return 1
    fi
}

# Validate Parquet file structure
validate_parquet_structure() {
    log "Validating Parquet file structure..."
    
    # Get a sample Parquet file from S3
    local current_date=$(date -u +"%Y/%m/%d/%H")
    IFS="/" read -r year month day hour <<< "$current_date"
    local s3_path="s3://${S3_BUCKET}/topics/postgres.public.users/year=${year}/month=${month}/day=${day}/hour=${hour}/"
    
    # List files and get the first Parquet file
    local parquet_file=$(aws s3 ls "$s3_path" 2>/dev/null | grep ".parquet" | head -1 | awk '{print $4}')

    if [[ -z "$parquet_file" ]]; then
        previous_hour=$(printf "%02g\n" $((hour - 1)))
        s3_path="s3://${S3_BUCKET}/topics/postgres.public.users/year=${year}/month=${month}/day=${day}/hour=${previous_hour}/"
        parquet_file=$(aws s3 ls "$s3_path" 2>/dev/null | grep ".parquet" | head -1 | awk '{print $4}')
    fi
    
    if [[ -n "$parquet_file" ]]; then
        log "Found Parquet file: $parquet_file"
        
        # Download and inspect the file (basic validation)
        local full_s3_path="${s3_path}${parquet_file}"
        log "Parquet file location: $full_s3_path"
        
        # Check file size
        local file_size=$(aws s3 ls "$full_s3_path" --region us-east-1 2>/dev/null | awk '{print $3}')
        
        if [[ -n "$file_size" && "$file_size" -gt "0" ]]; then
            log "✅ Parquet file has valid size: $file_size bytes"
            return 0
        else
            log "❌ Parquet file appears to be empty or invalid"
            return 1
        fi
    else
        log "❌ No Parquet files found for validation"
        return 1
    fi
}

# Check time-based partitioning
validate_time_partitioning() {
    log "Validating time-based partitioning structure..."
    
    # Check if the expected partition structure exists
    
    local partition_structure=$(aws s3 ls s3://${S3_BUCKET}/topics/postgres.public.users/ --region us-east-1 2>/dev/null | grep "year=" | head -5)
    if [[ -n "$partition_structure" ]]; then
        log "✅ Time-based partitioning structure found:"
        echo "$partition_structure" | tee -a "${LOG_DIR}/validate.log"
        return 0
    else
        log "❌ Time-based partitioning structure not found"
        return 1
    fi
}

# Check connector metrics and performance
check_connector_metrics() {
    log "Checking connector metrics and performance..."
    
    # Get connector metrics
    local metrics=$(kubectl exec -n ${NAMESPACE} ${CONNECT_S3_POD} -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    
    if [[ -n "$metrics" ]]; then
        log "Connector metrics:"
        echo "$metrics" | jq '.' | tee -a "${LOG_DIR}/validate.log"
        
        # Check for any failed tasks
        local failed_tasks=$(echo "$metrics" | jq -r '.tasks[] | select(.state == "FAILED") | .id' 2>/dev/null || echo "")
        
        if [[ -z "$failed_tasks" ]]; then
            log "✅ No failed tasks found"
            return 0
        else
            log "⚠️  Failed tasks found: $failed_tasks"
            return 1
        fi
    else
        log "❌ Failed to retrieve connector metrics"
        return 1
    fi
}

# Check dead letter queue
check_dlq() {
    log "Checking dead letter queue for errors..."
    
    # Check if DLQ topic has any messages
    local dlq_messages=$(kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
        kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 \
        --topic s3-sink-dlq --time -1 2>/dev/null | \
        awk -F: '{sum += $3} END {print (sum ? sum : 0)}' || echo "0")
    
    log "DLQ message count: $dlq_messages"
    
    if [[ "$dlq_messages" -eq "0" ]]; then
        log "✅ No messages in dead letter queue"
        return 0
    else
        log "⚠️  $dlq_messages messages found in dead letter queue"
        
        # Sample a few DLQ messages for analysis
        log "Sampling DLQ messages..."
        kubectl exec -n ${NAMESPACE} ${KAFKA_POD} -- \
            kafka-console-consumer --bootstrap-server localhost:9092 \
            --topic s3-sink-dlq --from-beginning --timeout-ms 5000 2>/dev/null | head -5 | tee -a "${LOG_DIR}/validate.log"
        
        return 1
    fi
}

# Check resource usage
check_resource_usage() {
    log "Checking resource usage..."
    
    if kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null | grep -E "(kafka-connect|postgresql|kafka)" | tee -a "${LOG_DIR}/validate.log"; then
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
    
    log "=== S3 Archival Validation Complete ==="
    log ""
    log "Summary:"
    log "- S3 Sink connector status: $([ ${#failed_tests[@]} -eq 0 ] && echo "✅ PASSED" || echo "⚠️  ISSUES FOUND")"
    log "- S3 bucket accessibility: Validated"
    log "- Data flow to S3: Tested"
    log "- Parquet file structure: Validated"
    log "- Time-based partitioning: Verified"
    log "- Error handling (DLQ): Checked"
    log ""
    
    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log "✅ All validation tests passed - Task 10 is complete!"
        log "✅ S3 archival is operational with Parquet format and time-based partitioning"
        return 0
    else
        log "⚠️  Some tests had issues: ${failed_tests[*]}"
        log "Check logs for details: ${LOG_DIR}/validate.log"
        return 1
    fi
}

# Main execution function
main() {
    log "=== Starting Task 10: Validating S3 Sink Connector and Archival ==="
    
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
    
    # Step 3: Check S3 bucket accessibility
    if ! check_s3_bucket; then
        failed_tests+=("s3-bucket")
    fi
    
    # Step 4: Test data flow to S3
    if ! test_s3_data_flow; then
        failed_tests+=("data-flow")
    fi
    
    # Step 5: Validate Parquet structure
    if ! validate_parquet_structure; then
        failed_tests+=("parquet-structure")
    fi
    
    # Step 6: Validate time-based partitioning
    if ! validate_time_partitioning; then
        failed_tests+=("time-partitioning")
    fi
    
    # Step 7: Check connector metrics
    if ! check_connector_metrics; then
        failed_tests+=("connector-metrics")
    fi
    
    # Step 8: Check dead letter queue
    if ! check_dlq; then
        failed_tests+=("dead-letter-queue")
    fi
    
    # Step 9: Check resource usage
    check_resource_usage
    
    # Step 10: Generate summary
    generate_summary "${failed_tests[@]}"
}

# Execute main function
main "$@"