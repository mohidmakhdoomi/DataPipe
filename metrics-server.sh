#!/bin/bash
# This script contains functions for the metrics server

readonly METRICS_FILE="components.yaml"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Check if metrics-server is available
check_metrics_server() {
    log "Checking if metrics-server is available..."
    
    if kubectl top nodes >/dev/null 2>&1; then
        log "SUCCESS! Metrics-server is available"
        return 0
    else
        log "WARNING! Metrics-server is not available"
        return 1
    fi
}

delete_old_metric_server() {
    # Check if metrics-server is already being installed
    if kubectl get deploy metrics-server -n kube-system >/dev/null 2>&1; then
        log "Clearing existing metrics-server deployment..."
        kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1
        kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml >/dev/null 2>&1
        kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability-1.21+.yaml >/dev/null 2>&1
        log "Done - existing metrics-server deployment removed"
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
    
    if kubectl apply -f ${METRICS_FILE} >/dev/null 2>&1; then
        log "Metrics-server installation initiated"

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
            log "Metrics-server FAILED to become ready"
            return 1
        fi
    else
        log "FAILED to install metrics-server"
        return 1
    fi
}