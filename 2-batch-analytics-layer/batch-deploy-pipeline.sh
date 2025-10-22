#!/bin/bash
# This script deploys the entire batch analytics pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly NAMESPACE="batch-analytics"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
readonly LOG_DIR="${SCRIPT_DIR}/../logs/$NAMESPACE/deploy-logs"
readonly LOG_FILE="${LOG_DIR}/main.log"
readonly LOG_MESSAGE_PREFIX="Deployment: "

readonly KIND_CONFIG="batch-kind-config.yaml"

readonly CONFIG_FILES=(
    "batch-01-namespace.yaml"
    "batch-02-service-accounts.yaml"
    "batch-storage-classes.yaml"
    "batch-pvcs.yaml"
)

# Load util functions and variables (if available)
if [[ -f "${SCRIPT_DIR}/../utils.sh" ]]; then
    source "${SCRIPT_DIR}/../utils.sh"
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Main execution
main() {
    log "========== Starting Batch Analytics Pipeline deployment =========="
    
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

    start_resource_monitor

    docker build -t spark:3.5.7-hadoop-aws-iceberg-snowflake -f "Dockerfile" .
    kind load docker-image spark:3.5.7-hadoop-aws-iceberg-snowflake -n batch-analytics
    
    for current_record in "${CONFIG_FILES[@]}"; do
        IFS=':' read -r current_file status_to_check waiting_identifier timeout_in_seconds number_of_items <<< "$current_record"
        log "Applying ${current_file}"
        if ! kubectl --context "kind-$NAMESPACE" apply -f ${SCRIPT_DIR}/${current_file} >/dev/null 2>&1; then
            log "❌ : Failed to apply ${current_file}"
            exit_one
        fi

        if [[ -n "$status_to_check" ]]; then
            local command_to_wait="kubectl --context \"kind-$NAMESPACE\" wait --for=condition=${status_to_check} ${waiting_identifier} -n ${NAMESPACE} --timeout=${timeout_in_seconds}s 2>&1"
            log "$command_to_wait"
            local status=$(eval "$command_to_wait")
            if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq $number_of_items ]]; then
                log "✅ ${waiting_identifier} is ${status_to_check}"
            else
                log "❌ : ${waiting_identifier} failed to become ${status_to_check} in ${timeout_in_seconds}s"
                kubectl --context "kind-$NAMESPACE" get all -n ${NAMESPACE} -o wide >> "${LOG_DIR}/main.log"
                exit_one
            fi
        fi
    done
    
    # Verify prerequisites
    if ! kubectl --context "kind-$NAMESPACE" get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ : Namespace ${NAMESPACE} not found"
        exit_one
    fi
    
    bash task2-deploy-spark-operator.sh

    bash task3-setup-s3-access.sh

    stop_monitoring

    log "========== SUCCESS - Batch Analytics Pipeline deployment completed =========="
    exit 0
}

# Execute main function
main "$@"