#!/bin/bash
# This script deploys the entire pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/deploy-logs"

readonly KIND_CONFIG="kind-config.yaml"
readonly NAMESPACE="data-ingestion"

readonly CONFIG_FILES=(
    "01-namespace.yaml"
    "02-service-accounts.yaml"
    "03-network-policies.yaml"
    "04-secrets.yaml"
    "storage-classes.yaml"
    "data-services-pvcs.yaml"
    "task4-postgresql-statefulset.yaml:ready:pod -l app=postgresql,component=database:60:1"
    "task5-kafka-kraft-3brokers.yaml:ready:pod -l app=kafka,component=streaming:150:3"
    "task5-cdc-topics-job.yaml:complete:job/create-cdc-topics:50:1"
    "task6-schema-registry.yaml:ready:pod -l app=schema-registry,component=schema-management:150:1"
    "task7-kafka-connect-topics.yaml:complete:job/kafka-connect-topics-setup:50:1"
    "task7-kafka-connect-deployment.yaml:ready:pod -l app=kafka-connect,component=worker:150:1"
)

readonly CONN_DEPLOY_SCRIPT="task9-deploy-connector.sh"
readonly CONN_CONFIGS=(
    "postgres-cdc-connector:task9-debezium-connector-config.json"
    "s3-sink-connector:task10-s3-sink-connector-config.json"
)

# Load functions for metrics server
source ${SCRIPT_DIR}/metrics-server.sh

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deployment: $*" | tee -a "${LOG_DIR}/main.log"
}

# Main execution
main() {
    log "========== Starting Data Ingestion Pipeline deployment =========="

    log "Deleting existing cluster if needed"
    if ! kind delete cluster -n ${NAMESPACE} >/dev/null 2>&1; then
        log "ERROR: Failed to delete existing cluster"
        exit 1
    fi

    log "Creating cluster using ${KIND_CONFIG}"
    if ! kind create cluster --config ${SCRIPT_DIR}/${KIND_CONFIG} >/dev/null 2>&1; then
        log "ERROR: Failed to create cluster"
        exit 1
    fi
    
    if ! install_metrics_server; then
        log "ERROR: metrics-server not available"
        exit 1
    fi

    for current_record in "${CONFIG_FILES[@]}"; do
        IFS=':' read -r current_file status_to_check waiting_identifier timeout_in_seconds number_of_items <<< "$current_record"
        log "Applying ${current_file}"
        if ! kubectl apply -f ${SCRIPT_DIR}/${current_file} >/dev/null 2>&1; then
            log "ERROR: Failed to apply ${current_file}"
            exit 1
        fi

        if [[ -n "$status_to_check" ]]; then
            local command_to_wait="kubectl wait --for=condition=${status_to_check} ${waiting_identifier} -n ${NAMESPACE} --timeout=${timeout_in_seconds}s 2>&1"
            log "$command_to_wait"
            local status=$(eval "$command_to_wait")
            if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq $number_of_items ]]; then
                log "${waiting_identifier} is ${status_to_check}"
            else
                log "${waiting_identifier} FAILED to become ${status_to_check} in ${timeout_in_seconds}s"
                kubectl get all -n ${NAMESPACE} -o wide >> "${LOG_DIR}/main.log"
                exit 1
            fi
        fi
    done
    
    # Verify prerequisites
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "ERROR: Namespace ${NAMESPACE} not found"
        exit 1
    fi

    for current_record in "${CONN_CONFIGS[@]}"; do
        IFS=':' read -r connector_name connector_config_file <<< "$current_record"
        log "Deploying Connector config ${connector_name}"
        if ! bash ${SCRIPT_DIR}/${CONN_DEPLOY_SCRIPT} ${connector_name} ${connector_config_file} 2>&1 | tee -a "${LOG_DIR}/main.log"; then
            log "ERROR: Failed to deploy ${connector_name} using config ${connector_config_file}"
            exit 1
        fi
    done

    log "========== SUCCESS - Data Ingestion Pipeline deployment completed =========="
    exit 0
}

# Execute main function
main "$@"