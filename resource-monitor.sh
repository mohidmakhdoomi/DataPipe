#!/bin/bash
# Task 8 Resource Monitor - Background monitoring script
# Based on Gemini's technical guidance for accurate resource measurement

readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/logs/resource-logs"
readonly NAMESPACE="data-ingestion"
readonly CRITICAL_THRESHOLD=3584  # 3.5Gi in Mi
readonly WARNING_THRESHOLD=3276   # 3.2Gi in Mi

mkdir -p "${LOG_DIR}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_DIR}/resource-monitor.log"
}

while true; do
    # Get memory usage from all pods in namespace
    resource_data=$(kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null || echo "")
    
    if [[ -n "$resource_data" ]]; then
        # Calculate total memory usage
        total_memory=0
        
        # Log individual pod usage
        while read -r line; do
            pod_name=$(echo "$line" | awk '{print $1}')
            pod_cpu=$(echo "$line" | awk '{print $2}')
            pod_memory=$(echo "$line" | awk '{print $3}' | sed 's/Mi//')
            if [[ $pod_memory == *Gi ]]; then
                pod_memory=`echo "${pod_memory%??} 1024" | awk '{print $1*$2}'`
            fi
            total_memory=$((total_memory + pod_memory))
            log "Pod: $pod_name | Memory: ${pod_memory}Mi | CPU: ${pod_cpu}"
        done <<< "$resource_data"

        # Log total and check thresholds
        log "Total Memory: ${total_memory}Mi / 4096Mi ($(($total_memory*100/4096))%)"
        log "======================================="
        
        # Alert on thresholds
        if (( $(($total_memory > $CRITICAL_THRESHOLD)) )); then
            log "CRITICAL: Memory usage ${total_memory}Mi exceeds critical threshold ${CRITICAL_THRESHOLD}Mi"
            # Could trigger circuit breaker here
        elif (( $(($total_memory > $WARNING_THRESHOLD)) )); then
            log "⚠️   Memory usage ${total_memory}Mi exceeds warning threshold ${WARNING_THRESHOLD}Mi"
        fi
        
        # Check for OOMKilled events
        oom_events=$(kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling --no-headers 2>/dev/null | wc -l)
        if [[ $oom_events -gt 0 ]]; then
            log "CRITICAL: $oom_events OOMKilled events detected!"
            kubectl get events -n ${NAMESPACE} --field-selector reason=OOMKilling >> "${LOG_DIR}/oom-events.log"
        fi
    else
        log "⚠️   Unable to retrieve pod metrics"
    fi
    
    sleep 10  # Check every 10 seconds
done