#!/bin/bash
# Deploy Connector for Kafka Connect
# This script deploys a connector using Kafka Connect REST API

set -euo pipefail
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="$1"
readonly CONFIG_FILE="$2"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/logs/data-ingestion-pipeline/deploy-logs"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploy Connector: $*" | tee -a "${LOG_DIR}/connector.log"
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if config file exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log "❌ : Configuration file $CONFIG_FILE not found"
        return 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ : Namespace ${NAMESPACE} not found"
        return 1
    fi
    
    log "✅  Prerequisites validated"
    return 0
}

# Wait for Kafka Connect to be ready
wait_for_kafka_connect() {
    log "Checking Kafka Connect service status..."
    kubectl get pods -n ${NAMESPACE} -l app=kafka-connect,component=worker | tee -a "${LOG_DIR}/connector.log"
    
    log "Waiting for Kafka Connect to be ready..."
    if kubectl wait --for=condition=ready pod -l app=kafka-connect,component=worker -n ${NAMESPACE} --timeout=300s; then
        log "✅  Kafka Connect is ready"
        return 0
    else
        log "❌ : Kafka Connect failed to become ready within 300s"
        return 1
    fi
}

# Check if connector exists and handle cleanup
handle_existing_connector() {
    log "Checking if connector already exists..."

    local status=$(kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status \
        2>/dev/null)
    
    # Check if connector already exists by trying to get its status
    if [[ -n "$status" ]] && echo "$status" | grep -qv "error_code\":404,\"message\":\"No status found for connector ${CONNECTOR_NAME}\""; then
        log "⚠️    Connector exists. Deleting existing connector..."
        if kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
           curl -X DELETE http://localhost:8083/connectors/${CONNECTOR_NAME} >/dev/null 2>&1; then
            log "✅  Existing connector deleted"
            log "Waiting 10 seconds for cleanup..."
            sleep 10
        else
            log "❌ : Failed to delete existing connector"
            return 1
        fi
    else
        log "✅  No existing connector found"
    fi
    
    return 0
}

# Deploy the connector
deploy_connector() {
    log "Deploying connector..."
    
    # Deploy connector via REST API
    if kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
       curl -X POST http://kafka-connect.${NAMESPACE}.svc.cluster.local:8083/connectors \
       -H "Content-Type: application/json" \
       -d "$(cat ${CONFIG_FILE})" >/dev/null 2>&1; then
        log "✅  Connector deployed successfully"
        return 0
    else
        log "❌ : Connector deployment failed"
        return 1
    fi
}

# Validate deployment
validate_deployment() {
    log "Checking connector status..."
    sleep 5
    
    local status_output=$(kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
        curl -s http://localhost:8083/connectors/${CONNECTOR_NAME}/status 2>/dev/null)
    
    if [[ -n "$status_output" ]]; then
        echo "$status_output" | jq '.' | tee -a "${LOG_DIR}/connector.log"
        
        # Check if connector is running
        local connector_state=$(echo "$status_output" | jq -r '.connector.state' 2>/dev/null || echo "UNKNOWN")
        if [[ "$connector_state" == "RUNNING" ]]; then
            log "✅  Connector is in RUNNING state"
        else
            log "⚠️    Connector state: $connector_state"
        fi
    else
        log "❌ : Failed to get connector status"
        return 1
    fi
    
    log "Listing all connectors..."
    kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
        curl -s http://localhost:8083/connectors 2>/dev/null | jq '.' | tee -a "${LOG_DIR}/connector.log"
    
    return 0
}

# Main execution function
main() {
    log "=== Starting Connector Deployment: Deploying ${CONNECTOR_NAME} ==="
    
    # Step 1: Validate prerequisites
    if ! validate_prerequisites; then
        log "❌ : Prerequisites validation failed"
        return 1
    fi
    
    # Step 2: Wait for Kafka Connect
    if ! wait_for_kafka_connect; then
        log "❌ : Kafka Connect readiness check failed"
        return 1
    fi
    
    # Step 3: Handle existing connector
    if ! handle_existing_connector; then
        log "❌ : Failed to handle existing connector"
        return 1
    fi
    
    # Step 4: Deploy connector
    if ! deploy_connector; then
        log "❌ : Connector deployment failed"
        return 1
    fi
    
    # Step 5: Validate deployment
    if ! validate_deployment; then
        log "❌ : Deployment validation failed"
        return 1
    fi
    
    log "✅  Connector Deployment completed successfully"
    return 0
}

# Execute main function
main "$@"