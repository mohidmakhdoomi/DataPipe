#!/bin/bash
# Shut down pods/scale down replicas

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/logs/startstop-logs"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Shutdown: $*" | tee -a "${LOG_DIR}/shutdown.log"
}

scale_down() {
    log "Starting to shutdown/scale down Kafka Connect > Schema Registry > Kafka > PostgreSQL"
    
    # Get current pod names
    local pg_pod=$(kubectl get pods -n ${NAMESPACE} -l app=postgresql,component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    local kafka_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka,component=streaming -o jsonpath='{.items[2].metadata.name}' 2>/dev/null || echo "")
    local connect_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka-connect,component=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    local schema_pod=$(kubectl get pods -n ${NAMESPACE} -l app=schema-registry,component=schema-management -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
       
    local deleted_pods=()

    if [[ -n "$connect_pod" ]]; then
        kubectl scale deploy kafka-connect -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for Kafka Connect to terminate..."
        if kubectl wait --for=delete pod -l app=kafka-connect,component=worker -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ Kafka Connect scaled to replicas=0"
            deleted_pods+=("$connect_pod")
        else
            log "⚠️ Kafka Connect failed to scale to replicas=0"
        fi
    else
        log "❌ : Kafka Connect pod not found"
    fi

    if [[ -n "$schema_pod" ]]; then
        kubectl scale deploy schema-registry -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for Schema Registry to terminate..."
        if kubectl wait --for=delete pod -l app=schema-registry,component=schema-management -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ Schema Registry scaled to replicas=0"
            deleted_pods+=("$schema_pod")
        else
            log "⚠️ Schema Registry failed to scale to replicas=0"
        fi
    else
        log "❌ : Schema Registry pod not found"
    fi

    if [[ -n "$kafka_pod" ]]; then
        kubectl scale sts kafka -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for Kafka to terminate..."
        local status=$(kubectl wait --for=delete pod -l app=kafka,component=streaming -n ${NAMESPACE} --timeout=300s 2>&1)
        if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq 3 ]]; then
            log "✅ Kafka scaled to replicas=0"
            deleted_pods+=("$kafka_pod")
        else
            log "⚠️ Kafka failed to scale to replicas=0"
        fi
    else
        log "❌ : Kafka pod not found"
    fi

    if [[ -n "$pg_pod" ]]; then
        kubectl scale sts postgresql -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for PostgreSQL to terminate..."
        if kubectl wait --for=delete pod -l app=postgresql,component=database -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ PostgreSQL scaled to replicas=0"
            deleted_pods+=("$pg_pod")
        else
            log "⚠️ PostgreSQL failed to scale to replicas=0"
        fi
    else
        log "❌ : PostgreSQL pod not found"
    fi
    
    if [[ ${#deleted_pods[@]} -lt 4 ]]; then
        log "⚠️ Not all pods were deleted successfully"
        return 1
    else
        log "✅ All pods were deleted successfully"
    fi

    return 0
}

# Main execution
main() {
    log "=== Shutting down Data Ingestion Pipeline - Scaling down replicas to 0 ==="
    
    if ! scale_down; then
        log "❌ : Shutdown failed"
        exit 1
    fi

    log "========== SUCCESS - Data Ingestion Pipeline shutdown completed =========="
    exit 0
}

# Execute main function
main "$@"