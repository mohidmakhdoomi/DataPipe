#!/bin/bash
# This script deploys the entire pipeline

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
LOG_DIR="${SCRIPT_DIR}/../logs/data-ingestion-pipeline/deploy-logs"
MONITOR_PID=0

readonly KIND_CONFIG="kind-config.yaml"
NAMESPACE="data-ingestion"

readonly CONFIG_FILES=(
    "01-namespace.yaml"
    "02-service-accounts.yaml"
    "03-network-policies.yaml"
    "04-secrets.yaml"
    "storage-classes.yaml"
    "data-services-pvcs.yaml"
    "task4-postgresql-statefulset.yaml:ready:pod -l app=postgresql,component=database:300:1"
    "task5-kafka-kraft-3brokers.yaml:ready:pod -l app=kafka,component=streaming:300:3"
    "task5-kafka-topics-job.yaml:complete:job/create-kafka-topics:120:1"
    "task6-schema-registry.yaml:ready:pod -l app=schema-registry,component=schema-management:300:1"
    "task7-kafka-connect-deployment.yaml:ready:pod -l app=kafka-connect,component=worker:300:1"
)

readonly CONN_DEPLOY_SCRIPT="task9-deploy-connector.sh"
readonly CONN_CONFIGS=(
    "postgres-cdc-users-connector:connectors/users-debezium-connector.json"
    "postgres-cdc-products-connector:connectors/products-debezium-connector.json"
    "postgres-cdc-orders-connector:connectors/orders-debezium-connector.json"
    "postgres-cdc-order-items-connector:connectors/order-items-debezium-connector.json"
    "s3-sink-users-connector:connectors/users-s3-sink-connector.json"
    "s3-sink-products-connector:connectors/products-s3-sink-connector.json"
    "s3-sink-orders-connector:connectors/orders-s3-sink-connector.json"
    "s3-sink-order-items-connector:connectors/order-items-s3-sink-connector.json"
    # "postgres-cdc-connector:task9-debezium-connector-config.json"
    # "s3-sink-connector:task10-s3-sink-connector-config.json"
)

readonly SAMPLE_DB_FILE="sample_data_postgres.sql"
readonly DB_USER=$(yq 'select(.metadata.name == "postgresql-credentials").data.username' 04-secrets.yaml | base64 --decode)
readonly DB_NAME=$(yq 'select(.metadata.name == "postgresql-credentials").data.database' 04-secrets.yaml | base64 --decode)

# Load functions for metrics server (if available)
if [[ -f "${SCRIPT_DIR}/../metrics-server.sh" ]]; then
    source "${SCRIPT_DIR}/../metrics-server.sh"
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deployment: $*" | tee -a "${LOG_DIR}/main.log"
}

stop_monitoring() {
    # Stop resource monitoring
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
    log "========== Starting Data Ingestion Pipeline deployment =========="

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
        export NAMESPACE="${NAMESPACE}"
        if ! install_metrics_server; then
            log "❌ : metrics-server not available"
            exit_one
        fi
    fi

    # Start background resource monitoring if available
    if [[ -f "${SCRIPT_DIR}/../resource-monitor.sh" ]]; then
        log "Starting background resource monitoring"
        bash "${SCRIPT_DIR}/../resource-monitor.sh" "$NAMESPACE" "${SCRIPT_DIR}/../logs/data-ingestion-pipeline/resource-logs" &
        MONITOR_PID=$!
    fi

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

    export SCRIPT_DIR="${SCRIPT_DIR}"

    for current_record in "${CONN_CONFIGS[@]}"; do
        IFS=':' read -r connector_name connector_config_file <<< "$current_record"
        log "Deploying Connector config ${connector_name}"
        if ! bash ${SCRIPT_DIR}/${CONN_DEPLOY_SCRIPT} ${connector_name} ${connector_config_file} 2>&1 | tee -a "${LOG_DIR}/main.log"; then
            log "❌ : Failed to deploy ${connector_name} using config ${connector_config_file}"
            exit_one
        fi
    done

    log "Sleeping 1 min before inserting Sample Data"
    sleep 60

    # Insert Sample Data into PostgreSQL
    log "Inserting Sample Data into PostgreSQL"
    if ! kubectl --context "kind-$NAMESPACE" cp -n ${NAMESPACE} -c postgresql ${SAMPLE_DB_FILE} postgresql-0:/tmp/${SAMPLE_DB_FILE} >/dev/null 2>&1; then
        log "❌ : Failed to copy sample data .sql file into PostgreSQL pod"
        exit_one
    fi
    if ! kubectl --context "kind-$NAMESPACE" exec -n ${NAMESPACE} pod/postgresql-0 -- sh -c "psql -U ${DB_USER} -d ${DB_NAME} -a -f /tmp/${SAMPLE_DB_FILE}" >/dev/null 2>&1; then
        log "❌ : Failed to insert sample data into PostgreSQL"
        exit_one
    fi

    log "Sleeping 2 mins after inserting Sample Data"
    sleep 120

    export LOG_DIR="${LOG_DIR}"

    log "Executing Data Generator - performance benchmark..."
    if python "${SCRIPT_DIR}/data-generator.py" --rate 4000 --duration 180; then
        log "✅ Data Generator completed successfully"
    else
        log "❌ : Data Generator failed"
        exit_onegit 
    fi

    log "Sleeping 2 mins after running Data Generator"
    sleep 120

    stop_monitoring

    log "========== SUCCESS - Data Ingestion Pipeline deployment completed =========="
    exit 0
}

# Execute main function
main "$@"