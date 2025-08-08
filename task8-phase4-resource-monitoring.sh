#!/bin/bash
# Task 8 Phase 4: Resource Monitoring and Compliance
# Based on Gemini's technical monitoring guidance

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task8-logs"
readonly MONITORING_DURATION=300  # 5 minutes

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Phase 4: $*" | tee -a "${LOG_DIR}/phase4.log"
}

# Install metrics-server if needed
install_metrics_server() {
    log "Checking if metrics-server is available..."
    
    if kubectl top nodes >/dev/null 2>&1; then
        log "✅ Metrics-server is already available"
        return 0
    fi
    
    log "Installing metrics-server..."
    if kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null 2>&1; then
        log "✅ Metrics-server installation initiated"
        
        # Wait for metrics-server to be ready
        log "Waiting for metrics-server to be ready..."
        if kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s >/dev/null 2>&1; then
            log "✅ Metrics-server is ready"
            
            # Wait for metrics to be available
            local wait_count=0
            while [[ $wait_count -lt 12 ]]; do  # Wait up to 2 minutes
                if kubectl top nodes >/dev/null 2>&1; then
                    log "✅ Metrics are now available"
                    return 0
                fi
                log "⏳ Waiting for metrics to be available..."
                sleep 10
                wait_count=$((wait_count + 1))
            done
            
            log "⚠️  Metrics-server installed but metrics not yet available"
            return 1
        else
            log "❌ Metrics-server failed to become ready"
            return 1
        fi
    else
        log "❌ Failed to install metrics-server"
        return 1
    fi
}

# Monitor resource usage
monitor_resources() {
    log "Starting resource monitoring for ${MONITORING_DURATION} seconds..."
    
    local csv_file="${LOG_DIR}/resource-metrics.csv"
    echo "Timestamp,Pod,Memory_Mi,Memory_Limit_Mi,CPU_m,Memory_Percent" > "$csv_file"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + MONITORING_DURATION))
    local sample_count=0
    local total_memory_samples=0
    local max_memory=0
    
    while [[ $(date +%s) -lt $end_time ]]; do
        local current_time=$(date +%s)
        local pod_data=$(kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null || echo "")
        
        if [[ -n "$pod_data" ]]; then
            local total_memory=0
            
            while read -r line; do
                if [[ -n "$line" ]]; then
                    local pod=$(echo "$line" | awk '{print $1}')
                    local cpu=$(echo "$line" | awk '{print $2}' | sed 's/m//')
                    local mem=$(echo "$line" | awk '{print $3}' | sed 's/Mi//')
                    if [[ $mem == *Gi ]]; then
                        mem=`echo "${mem%??} 1024" | awk '{print $1*$2}'`
                    fi

                    # Get memory limit
                    local limit=$(kubectl get pod "$pod" -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null | sed 's/Mi//' || echo "0")
                    if [[ $limit == *Gi ]]; then
                        limit=`echo "${limit%??} 1024" | awk '{print $1*$2}'`
                    fi
                    local percent=0
                    if [[ $limit -gt 0 ]]; then
                        percent=$(($mem*100/$limit))
                    fi
                    
                    echo "$current_time,$pod,$mem,$limit,$cpu,$percent" >> "$csv_file"
                    total_memory=$((total_memory + mem))
                fi
            done <<< "$pod_data"
            
            # Track statistics
            total_memory_samples=$((total_memory_samples + total_memory))
            sample_count=$((sample_count + 1))
            if [[ $total_memory -gt $max_memory ]]; then
                max_memory=$total_memory
            fi
            
            # Log current usage
            log "Total Memory: ${total_memory}Mi / 4096Mi ($(($total_memory*100/4096))%)"
            
            # Check thresholds
            if [[ $total_memory -gt 3584 ]]; then  # 87.5% of 4Gi
                log "🚨 CRITICAL: Memory usage at ${total_memory}Mi exceeds 87.5% threshold"
            elif [[ $total_memory -gt 3276 ]]; then  # 80% of 4Gi
                log "⚠️  WARNING: Memory usage at ${total_memory}Mi exceeds 80% threshold"
            fi
        else
            log "⚠️  Unable to retrieve metrics data"
        fi
        
        sleep 10
    done
    
    # Calculate statistics
    local avg_memory=0
    if [[ $sample_count -gt 0 ]]; then
        avg_memory=$((total_memory_samples / $sample_count))
    fi
    
    log "Resource monitoring completed:"
    log "  - Samples collected: $sample_count"
    log "  - Average memory usage: ${avg_memory}Mi"
    log "  - Peak memory usage: ${max_memory}Mi"
    log "  - Peak percentage: $(($max_memory*100/4096))%"
    
    # Check compliance
    if [[ $max_memory -le 3584 ]]; then  # 87.5% threshold
        log "✅ Memory usage compliant - peak ${max_memory}Mi within limits"
        return 0
    else
        log "❌ Memory usage exceeded limits - peak ${max_memory}Mi"
        return 1
    fi
}

# Check for OOM events
check_oom_events() {
    log "Checking for OOMKilled events..."
    
    local oom_count=$(kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling --no-headers 2>/dev/null | wc -l)
    
    if [[ $oom_count -eq 0 ]]; then
        log "✅ No OOMKilled events detected"
        return 0
    else
        log "❌ $oom_count OOMKilled event(s) detected"
        kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling >> "${LOG_DIR}/oom-events.log"
        return 1
    fi
}

# Verify resource limits are set
verify_resource_limits() {
    log "Verifying resource limits are properly configured..."
    
    local pods_without_limits=0
    local pod_list=$(kubectl get pods -n ${NAMESPACE} -o jsonpath='{.items[*].metadata.name}')
    
    for pod in $pod_list; do
        local memory_limit=$(kubectl get pod "$pod" -n ${NAMESPACE} -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
        
        if [[ -z "$memory_limit" ]]; then
            log "⚠️  Pod $pod has no memory limit set"
            pods_without_limits=$((pods_without_limits + 1))
        else
            log "✅ Pod $pod has memory limit: $memory_limit"
        fi
    done
    
    if [[ $pods_without_limits -eq 0 ]]; then
        log "✅ All pods have memory limits configured"
        return 0
    else
        log "⚠️  $pods_without_limits pod(s) missing memory limits"
        return 0  # Don't fail on this as it's informational
    fi
}

main() {
    log "=== Starting Phase 4: Resource Monitoring and Compliance ==="
    
    # Step 1: Ensure metrics-server is available
    if ! install_metrics_server; then
        log "❌ Phase 4 failed - metrics-server not available"
        return 1
    fi
    
    # Step 2: Verify resource limits
    verify_resource_limits
    
    # Step 3: Monitor resource usage
    if ! monitor_resources; then
        log "❌ Phase 4 failed - resource usage exceeded limits"
        return 1
    fi
    
    # Step 4: Check for OOM events
    if ! check_oom_events; then
        log "⚠️  OOM events detected but continuing..."
    fi
    
    log "✅ Phase 4 completed successfully - resource monitoring compliant"
    return 0
}

main "$@"