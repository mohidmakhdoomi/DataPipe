#!/bin/bash
# Start up pods/scale up replicas

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
readonly LOG_DIR="${SCRIPT_DIR}/../logs/$NAMESPACE/startstop-logs"
readonly LOG_FILE="${LOG_DIR}/startup.log"
readonly LOG_MESSAGE_PREFIX="Startup: "

mkdir -p "${LOG_DIR}"

# Load util functions and variables (if available)
if [[ -f "${SCRIPT_DIR}/../utils.sh" ]]; then
    source "${SCRIPT_DIR}/../utils.sh"
fi

scale_up() {
    log "Starting up/scale up PostgreSQL > Kafka > Schema Registry > Kafka Connect"

    local started_pods=()
    
    # Wait for PostgreSQL
    log "Scaling PostgreSQL to replicas=1"
    kubectl --context "kind-$NAMESPACE" scale sts postgresql -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for PostgreSQL to be ready..."
    if kubectl --context "kind-$NAMESPACE" wait --for=condition=ready pod -l app=postgresql,component=database -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ PostgreSQL pod started and ready"
        started_pods+=("PostgreSQL")
    else
        log "⚠️  PostgreSQL pod start timeout (may still be starting)"
    fi
    
    # Wait for Kafka
    log "Scaling Kafka to replicas=3"
    kubectl --context "kind-$NAMESPACE" scale sts kafka -n ${NAMESPACE} --replicas=3 >/dev/null 2>&1 &
    log "Waiting for Kafka to be ready..."
    local status=$(kubectl --context "kind-$NAMESPACE" wait --for=condition=ready pod -l app=kafka,component=streaming -n ${NAMESPACE} --timeout=300s 2>&1)
    if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq 3 ]]; then
        log "✅ Kafka pods started and ready"
        started_pods+=("Kafka")
    else
        log "⚠️  Kafka pod start timeout (may still be starting)"
    fi
    
    # Wait for Schema Registry
    log "Scaling Schema Registry to replicas=1"
    kubectl --context "kind-$NAMESPACE" scale deploy schema-registry -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for Schema Registry to be ready..."
    if kubectl --context "kind-$NAMESPACE" wait --for=condition=ready pod -l app=schema-registry,component=schema-management -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ Schema Registry pod started and ready"
        started_pods+=("Schema Registry")
    else
        log "⚠️  Schema Registry pod start timeout (may still be starting)"
    fi

    # Wait for Kafka Connect
    log "Scaling Kafka Connect to replicas=1"
    kubectl --context "kind-$NAMESPACE" scale deploy kafka-connect -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for Kafka Connect to be ready..."
    if kubectl --context "kind-$NAMESPACE" wait --for=condition=ready pod -l app=kafka-connect,component=worker -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ Kafka Connect pod started and ready"
        started_pods+=("Kafka Connect")
    else
        log "⚠️  Kafka Connect pod start timeout (may still be starting)"
    fi
    
    if [[ ${#started_pods[@]} -lt 4 ]]; then
        log "⚠️ Not all pods were started successfully"
        return 1
    else
        log "✅ All pods were started successfully"
    fi

    # Additional stabilization time
    log "Allowing 60s additional stabilization time..."
    sleep 60

    return 0
}

# Main execution
main() {
    log "=== Starting up Data Ingestion Pipeline - Scaling up replicas ==="

    if ! scale_up; then
        log "❌ : Startup failed"
        exit 1
    fi

    log "========== SUCCESS - Data Ingestion Pipeline startup completed =========="
    exit 0
}

# Execute main function
main "$@"