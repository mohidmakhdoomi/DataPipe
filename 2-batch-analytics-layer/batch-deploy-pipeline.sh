#!/bin/bash
# This script deploys the entire batch analytics pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG_DIR="${SCRIPT_DIR}/../logs/batch-analytics-layer/deploy-logs"
MONITOR_PID=0

readonly KIND_CONFIG="batch-kind-config.yaml"
readonly NAMESPACE="batch-analytics"

readonly CONFIG_FILES=(
    "batch-01-namespace.yaml"
    "batch-02-service-accounts.yaml"
    "batch-storage-classes.yaml"
    "batch-pvcs.yaml"
)

# Load functions for metrics server (if available)
if [[ -f "${SCRIPT_DIR}/../metrics-server.sh" ]]; then
    source "${SCRIPT_DIR}/../metrics-server.sh"
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Batch Deployment: $*" | tee -a "${LOG_DIR}/main.log"
}

stop_monitoring() {
    # Stop resource monitoring if running
    if [[ "$MONITOR_PID" -ne 0 ]]; then
        log "Stopping background resource monitoring"
        kill $MONITOR_PID 2>/dev/null || true
    fi
}

exit_one() {
    stop_monitoring
    exit 1
}

# Main execution
main() {
    log "========== Starting Batch Analytics Pipeline deployment =========="

    export SCRIPT_DIR="${SCRIPT_DIR}"
    
    log "Deleting existing cluster if needed"
    if ! kind delete cluster -n ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ : Failed to delete existing cluster"
        exit_one
    fi

    log "Creating cluster using ${KIND_CONFIG}"
    if ! kind create cluster --config ${SCRIPT_DIR}/${KIND_CONFIG} >/dev/null 2>&1; then
        log "❌ : Failed to create cluster"
        exit_one
    fi
    
    # Install metrics server if available
    if command -v install_metrics_server >/dev/null 2>&1; then
        if ! install_metrics_server; then
            log "❌ : metrics-server not available"
            exit_one
        fi
    fi

    # Start background resource monitoring if available
    if [[ -f "${SCRIPT_DIR}/../resource-monitor.sh" ]]; then
        log "Starting background resource monitoring"
        bash "${SCRIPT_DIR}/../resource-monitor.sh" "$NAMESPACE" "${SCRIPT_DIR}/../logs/batch-analytics-layer/resource-logs" &
        MONITOR_PID=$!
    fi
    
    for current_record in "${CONFIG_FILES[@]}"; do
        IFS=':' read -r current_file status_to_check waiting_identifier timeout_in_seconds number_of_items <<< "$current_record"
        log "Applying ${current_file}"
        if ! kubectl apply -f ${SCRIPT_DIR}/${current_file} >/dev/null 2>&1; then
            log "❌ : Failed to apply ${current_file}"
            exit_one
        fi

        if [[ -n "$status_to_check" ]]; then
            local command_to_wait="kubectl wait --for=condition=${status_to_check} ${waiting_identifier} -n ${NAMESPACE} --timeout=${timeout_in_seconds}s 2>&1"
            log "$command_to_wait"
            local status=$(eval "$command_to_wait")
            if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq $number_of_items ]]; then
                log "✅ ${waiting_identifier} is ${status_to_check}"
            else
                log "❌ : ${waiting_identifier} failed to become ${status_to_check} in ${timeout_in_seconds}s"
                kubectl get all -n ${NAMESPACE} -o wide >> "${LOG_DIR}/main.log"
                exit_one
            fi
        fi
    done
    
    # Verify prerequisites
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ : Namespace ${NAMESPACE} not found"
        exit_one
    fi

    stop_monitoring

    log "========== SUCCESS - Batch Analytics Pipeline deployment completed =========="
    exit 0
}

# Execute main function
main "$@"