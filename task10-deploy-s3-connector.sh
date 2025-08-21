#!/bin/bash
# Task 10: Deploy Kafka Connect S3 Sink Connector
# This script deploys the S3 Sink connector using Kafka Connect REST API

set -euo pipefail
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="s3-sink-connector"
readonly CONFIG_FILE="task10-s3-sink-connector-config.json"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task10-logs"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Task 10 Deploy: $*" | tee -a "${LOG_DIR}/deploy.log"
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "❌ Configuration file $CONFIG_FILE not found"
        return 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ Namespace ${NAMESPACE} not found"
        return 1
    fi
    
    # Check if S3 Kafka Connect deployment exists
    if ! kubectl get deployment kafka-connect-s3 -n ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ Kafka Connect S3 deployment not found. Deploy task10-kafka-connect-s3-deployment.yaml first"
        return 1
    fi
    
    log "✅ Prerequisites validated"
    return 0
}

# Wait for Kafka Connect S3 to be ready
wait_for_kafka_connect_s3() {
    log "Checking Kafka Connect S3 service status..."
    kubectl get pods -n ${NAMESPACE} -l app=kafka-connect-s3,component=worker | tee -a "${LOG_DIR}/deploy.log"
    
    log "Waiting for Kafka Connect S3 to be ready..."
    if kubectl wait --for=condition=ready pod -l app=kafka-connect-s3,component=worker -n ${NAMESPACE} --timeout=300s; then
        log "✅ Kafka Connect S3 is ready"
        return 0
    else
        log "❌ Kafka Connect S3 failed to become ready within 300s"
        return 1
    fi
}

# Check if connector exists and handle cleanup
handle_existing_connector() {
    log "Checking if S3 Sink connector already exists..."

    local status=$(kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status \
        2>/dev/null)
    
    # Check if connector already exists
    if [[ -n "$status" ]] && echo "$status" | grep -qv "error_code\":404,\"message\":\"No status found for connector ${CONNECTOR_NAME}\""; then
        log "⚠️  S3 Sink connector exists. Deleting existing connector..."
        if kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
           curl -X DELETE http://localhost:8083/connectors/${CONNECTOR_NAME} >/dev/null 2>&1; then
            log "✅ Existing connector deleted"
            log "Waiting 10 seconds for cleanup..."
            sleep 10
        else
            log "❌ Failed to delete existing connector"
            return 1
        fi
    else
        log "✅ No existing connector found"
    fi
    
    return 0
}

# Deploy the S3 Sink connector
deploy_connector() {
    log "Deploying S3 Sink connector..."
    
    # Deploy connector via REST API
    if kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
       curl -X POST http://kafka-connect-s3.${NAMESPACE}.svc.cluster.local:8083/connectors \
       -H "Content-Type: application/json" \
       -d "$(cat ${CONFIG_FILE})" >/dev/null 2>&1; then
        log "✅ S3 Sink connector deployed successfully"
        return 0
    else
        log "❌ S3 Sink connector deployment failed"
        return 1
    fi
}

# Validate deployment
validate_deployment() {
    log "Checking S3 Sink connector status..."
    sleep 5
    
    local status_output=$(kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    
    if [[ -n "$status_output" ]]; then
        echo "$status_output" | jq '.' | tee -a "${LOG_DIR}/deploy.log"
        
        # Check if connector is running
        local connector_state=$(echo "$status_output" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
        if [[ "$connector_state" == "RUNNING" ]]; then
            log "✅ S3 Sink connector is in RUNNING state"
        else
            log "⚠️  S3 Sink connector state: $connector_state"
        fi
    else
        log "❌ Failed to get connector status"
        return 1
    fi
    
    log "Listing all connectors..."
    kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
        curl -s http://localhost:8083/connectors 2>/dev/null | jq '.' | tee -a "${LOG_DIR}/deploy.log"
    
    return 0
}

# Check S3 connectivity
test_s3_connectivity() {
    log "Testing S3 connectivity..."
    
    # Test AWS credentials and S3 access
    if kubectl exec -n ${NAMESPACE} deploy/kafka-connect-s3 -- \
       sh -c 'aws s3 ls s3://data-lake-ingestion-datapipe/ --region us-east-1' >/dev/null 2>&1; then
        log "✅ S3 connectivity test passed"
        return 0
    else
        log "⚠️  S3 connectivity test failed - check AWS credentials and bucket permissions"
        return 1
    fi
}

# Main execution function
main() {
    log "=== Starting Task 10: Deploying S3 Sink Connector ==="
    
    # Step 1: Validate prerequisites
    if ! validate_prerequisites; then
        log "❌ Prerequisites validation failed"
        return 1
    fi
    
    # Step 2: Wait for Kafka Connect S3
    if ! wait_for_kafka_connect_s3; then
        log "❌ Kafka Connect S3 readiness check failed"
        return 1
    fi
    
    # Step 3: Handle existing connector
    if ! handle_existing_connector; then
        log "❌ Failed to handle existing connector"
        return 1
    fi
    
    # Step 4: Test S3 connectivity
    test_s3_connectivity
    
    # Step 5: Deploy connector
    if ! deploy_connector; then
        log "❌ Connector deployment failed"
        return 1
    fi
    
    # Step 6: Validate deployment
    if ! validate_deployment; then
        log "❌ Deployment validation failed"
        return 1
    fi
    
    log "✅ Task 10 Deployment completed successfully"
    log "Run task10-validate-s3-archival.sh to validate the S3 archival functionality"
    return 0
}

# Execute main function
main "$@"