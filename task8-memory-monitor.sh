#!/bin/bash
# Task 8 Memory Monitor - Background monitoring script
# Based on Gemini's technical guidance for accurate memory measurement

readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task8-logs"
readonly NAMESPACE="data-ingestion"
readonly CRITICAL_THRESHOLD=3584  # 3.5Gi in Mi
readonly WARNING_THRESHOLD=3276   # 3.2Gi in Mi

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_DIR}/memory-monitor.log"
}

log "Starting memory monitoring for Task 8 validation"

while true; do
    # Get memory usage from all pods in namespace
    memory_data=$(kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null || echo "")
    
    if [[ -n "$memory_data" ]]; then
        # Calculate total memory usage
        total_memory=$(echo "$memory_data" | awk '{sum+=$3+0} END {print sum}')
        
        # Log individual pod usage
        echo "$memory_data" | while read -r line; do
            pod_name=$(echo "$line" | awk '{print $1}')
            pod_memory=$(echo "$line" | awk '{print $3}')
            log "Pod: $pod_name Memory: ${pod_memory}Mi"
        done
        
        # Log total and check thresholds
        percentage=$(echo "scale=1; $total_memory/4096*100" | bc -l 2>/dev/null || echo "0")
        log "Total Memory: ${total_memory}Mi / 4096Mi (${percentage}%)"
        
        # Alert on thresholds
        if (( $(echo "$total_memory > $CRITICAL_THRESHOLD" | bc -l) )); then
            log "🚨 CRITICAL: Memory usage ${total_memory}Mi exceeds critical threshold ${CRITICAL_THRESHOLD}Mi"
            # Could trigger circuit breaker here
        elif (( $(echo "$total_memory > $WARNING_THRESHOLD" | bc -l) )); then
            log "⚠️  WARNING: Memory usage ${total_memory}Mi exceeds warning threshold ${WARNING_THRESHOLD}Mi"
        fi
        
        # Check for OOMKilled events
        oom_events=$(kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling --no-headers 2>/dev/null | wc -l)
        if [[ $oom_events -gt 0 ]]; then
            log "🚨 CRITICAL: $oom_events OOMKilled events detected!"
            kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling >> "${LOG_DIR}/oom-events.log"
        fi
    else
        log "WARNING: Unable to retrieve pod memory metrics"
    fi
    
    sleep 10  # Check every 10 seconds
done