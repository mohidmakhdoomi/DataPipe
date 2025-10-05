#!/bin/bash
# This script contains utility functions and variables

namespace_limit() {
    NAMESPACE_MEMORY=$(eval "yq 'select(.metadata.name == \"$NAMESPACE-quota\").spec.hard.\"limits.memory\"' ${SCRIPT_DIR}/../*$NAMESPACE*/*01-namespace.yaml" | sed 's/Mi//')
    if [[ $NAMESPACE_MEMORY == *Gi ]]; then
        NAMESPACE_MEMORY=$(echo "${NAMESPACE_MEMORY%??} 1024" | awk '{print $1*$2}')
    fi
    echo $NAMESPACE_MEMORY
}

MEMORY_LIMIT=$(namespace_limit)
CRITICAL_THRESHOLD=$(echo "${MEMORY_LIMIT} 0.875" | awk '{print int($1*$2)}')
WARNING_THRESHOLD=$(echo "${MEMORY_LIMIT} 0.8" | awk '{print int($1*$2)}')

MONITOR_PID=0

METRICS_FILE="components.yaml"

RED_MSG='\033[0;31m'
GREEN_MSG='\033[0;32m'
YELLOW_MSG='\033[1;33m'
BLUE_MSG='\033[0;34m'
NC_MSG='\033[0m' # No Color

# Logging function
log() {
    # Colors for output


    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local level=$1
    if [[ "$level" != "DEBUG" || "${VERBOSE:-false}" == "true" ]]; then
        local color_var
        case $level in
            INFO) color_var=${BLUE_MSG};shift ;;
            WARN)  color_var=${YELLOW_MSG};shift ;;
            ERROR) color_var=${RED_MSG};shift ;;
            SUCCESS) color_var=${GREEN_MSG};shift ;;
            DEBUG) color_var=${NC_MSG};shift ;;
            *) color_var=${BLUE_MSG};level="INFO" ;;
        esac    
        local message="${LOG_MESSAGE_PREFIX:-}$*"
        if [[ "${LOG_FILE_ONLY:-false}" == "false" ]]; then
            echo -e "[$timestamp] ${color_var}[$level]${NC_MSG} $message"
        fi
        if [[ -n "${LOG_FILE:-}" ]]; then
            echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
        fi
    fi
}

start_resource_monitor() {
    # Start background resource monitoring if available
    if [[ -f "${SCRIPT_DIR}/../resource-monitor.sh" ]]; then
        log "Starting background resource monitoring"
        bash "${SCRIPT_DIR}/../resource-monitor.sh" "$NAMESPACE" "${SCRIPT_DIR}/../logs/$NAMESPACE/resource-logs" &
        MONITOR_PID=$!
    fi
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

# Check if metrics-server is available
check_metrics_server() {
    log "Checking if metrics-server is available..."

    kubectl --context "kind-$NAMESPACE" top nodes >/dev/null 2>&1
    local metrics_status=$?

    if [[ $metrics_status -eq 0 ]]; then
        log "✅ Metrics-server is available"
        return 0
    else
        log "⚠️   Metrics-server is not available"
        return 1
    fi
}

delete_old_metric_server() {
    kubectl --context "kind-$NAMESPACE" get deploy metrics-server -n kube-system >/dev/null 2>&1
    local metrics_status=$?

    # Check if metrics-server is already being installed
    if [[ $metrics_status -eq 0 ]]; then
        log "Clearing existing metrics-server deployment..."
        kubectl --context "kind-$NAMESPACE" delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1
        kubectl --context "kind-$NAMESPACE" delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml >/dev/null 2>&1
        kubectl --context "kind-$NAMESPACE" delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability-1.21+.yaml >/dev/null 2>&1
        log "✅ - existing metrics-server deployment removed"
    fi
}

# Install metrics-server if needed
install_metrics_server() {
    if check_metrics_server; then
        return 0
    fi

    delete_old_metric_server
    
    log "Installing metrics-server..."
    rm -f components.yaml >/dev/null 2>&1
    rm -f high-availability.yaml >/dev/null 2>&1
    rm -f high-availability-1.21+.yaml >/dev/null 2>&1
    curl -L -o ${METRICS_FILE} "https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/${METRICS_FILE}" >/dev/null 2>&1
    sed -i "s/        - --metric-resolution=15s/        - --metric-resolution=15s\r\n        - --kubelet-insecure-tls/g" ${METRICS_FILE} >/dev/null 2>&1
    
    kubectl --context "kind-$NAMESPACE" apply -f ${METRICS_FILE} >/dev/null 2>&1
    local apply_status=$?

    if [[ $apply_status -eq 0 ]]; then
        log "Metrics-server installation initiated"

        # Wait for metrics-server to be ready
        log "Waiting for metrics-server to be ready..."
        local status=$(kubectl --context "kind-$NAMESPACE" wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=60s 2>&1)
        if [[ -n "$status" ]] && echo "$status" | grep "pod/metrics-server" | grep -q "condition met"; then
            log "Metrics-server is ready"
            
            # Wait for metrics to be available
            local wait_count=0
            while [[ $wait_count -lt 12 ]]; do  # Wait up to 2 minutes
                if kubectl --context "kind-$NAMESPACE" top nodes >/dev/null 2>&1; then
                    log "✅ Metrics are now available"
                    rm -f ${METRICS_FILE} >/dev/null 2>&1
                    return 0
                fi
                log "Waiting for metrics to be available..."
                sleep 10
                wait_count=$((wait_count + 1))
            done
            
            log "Metrics-server installed but metrics not yet available!"
            return 1
        else
            log "❌ : Metrics-server FAILED to become ready"
            return 1
        fi
    else
        log "❌ : Failed to install metrics-server"
        return 1
    fi
}