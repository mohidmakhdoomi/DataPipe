#!/bin/bash
# This script deploys the entire pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly NAMESPACE="data-ingestion"
readonly CONNECTOR_NAME="postgres-cdc-connector"
readonly LOG_DIR="${SCRIPT_DIR}/deploy-logs"

readonly KIND_CONFIG="kind-config.yaml"
readonly CONN_CONFIG_FILE="task9-debezium-connector-config.json"
readonly CONN_CONFIG_DEPLOY="task9-deploy-connector.sh"
readonly CONFIG_FILES=(
        "01-namespace.yaml"
        "02-service-accounts.yaml"
        "03-network-policies.yaml"
        "04-secrets.yaml"
        "storage-classes.yaml"
        "data-services-pvcs.yaml"
        "task4-postgresql-statefulset.yaml:ready:pod -l app=postgresql,component=database:45:1"
        "task5-kafka-kraft-3brokers.yaml:ready:pod -l app=kafka,component=streaming:105:3"
        "task5-cdc-topics-job.yaml:complete:job/create-cdc-topics:90:1"
        "task6-schema-registry.yaml:ready:pod -l app=schema-registry,component=schema-management:108:1"
        "task7-kafka-connect-topics.yaml:complete:job/kafka-connect-topics-setup:41:1"
        "task7-kafka-connect-deployment.yaml:ready:pod -l app=kafka-connect,component=worker:120:1"
    )

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deployment: $*" | tee -a "${LOG_DIR}/main.log"
}

# Install metrics-server if needed
install_metrics_server() {
    log "Checking if metrics-server is available..."
    
    if kubectl top nodes >/dev/null 2>&1; then
        log "Metrics-server is already available"
        return 0
    fi
    
    log "Installing metrics-server..."
    if kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1; then
        log "Metrics-server installation initiated"
        
        # Add --kubelet-insecure-tls flag
        log $(kubectl get deploy metrics-server -n kube-system -o yaml > components.yaml && sed -i "s/        - --metric-resolution=15s/        - --metric-resolution=15s\r\n        - --kubelet-insecure-tls/g" components.yaml && kubectl replace -f components.yaml && rm components.yaml)

        # Wait for metrics-server to be ready
        log "Waiting for metrics-server to be ready..."
        local status=$(kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s 2>&1)
        if [[ -n "$status" ]] && echo "$status" | grep "pod/metrics-server" | grep -q "condition met"; then
            log "Metrics-server is ready"
            
            # Wait for metrics to be available
            local wait_count=0
            while [[ $wait_count -lt 12 ]]; do  # Wait up to 2 minutes
                if kubectl top nodes >/dev/null 2>&1; then
                    log "Metrics are now available"
                    return 0
                fi
                log "Waiting for metrics to be available..."
                sleep 10
                wait_count=$((wait_count + 1))
            done
            
            log "Metrics-server installed but metrics not yet available!"
            return 1
        else
            log "Metrics-server FAILED to become ready"
            return 1
        fi
    else
        log "FAILED to install metrics-server"
        return 1
    fi
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

    log "Deploying Debezium CDC connector using ${CONN_CONFIG_DEPLOY}"
    if ! bash ${SCRIPT_DIR}/${CONN_CONFIG_DEPLOY} 2>&1 | tee -a "${LOG_DIR}/main.log"; then
        log "ERROR: Failed to execute ${CONN_CONFIG_DEPLOY}"
        exit 1
    fi

    log "========== SUCCESS - Data Ingestion Pipeline deployment completed =========="
    exit 0
}

# Execute main function
main "$@"