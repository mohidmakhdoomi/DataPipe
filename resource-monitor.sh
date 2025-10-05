#!/bin/bash
# Resource Monitor - Background monitoring script

readonly NAMESPACE="$1"
readonly LOG_DIR="$2"

readonly LOG_FILE="${LOG_DIR}/resource-monitor.log"
readonly LOG_FILE_ONLY=true
readonly SCRIPT_DIR="${SCRIPT_DIR:-$(pwd)}"

# Load util functions and variables (if available)
if [[ -f "${SCRIPT_DIR}/../utils.sh" ]]; then
    source "${SCRIPT_DIR}/../utils.sh"
fi

mkdir -p "${LOG_DIR}"

while true; do
    # Get memory usage from all pods in namespace
    resource_data=$(kubectl --context "kind-$NAMESPACE" top pods -n ${NAMESPACE} --no-headers 2>/dev/null || echo "")
    
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
        log "Total Memory: ${total_memory}Mi / "$MEMORY_LIMIT"Mi ($(($total_memory*100/$MEMORY_LIMIT))%)"
        log "======================================="
        
        # Alert on thresholds
        if (( $(($total_memory > $CRITICAL_THRESHOLD)) )); then
            log "CRITICAL: Memory usage ${total_memory}Mi exceeds critical threshold ${CRITICAL_THRESHOLD}Mi"
            # Could trigger circuit breaker here
        elif (( $(($total_memory > $WARNING_THRESHOLD)) )); then
            log "⚠️   Memory usage ${total_memory}Mi exceeds warning threshold ${WARNING_THRESHOLD}Mi"
        fi
        
        # Check for OOMKilled events
        oom_events=$(kubectl --context "kind-$NAMESPACE" get events -n ${NAMESPACE} --field-selector reason=OOMKilling --no-headers 2>/dev/null | wc -l)
        if [[ $oom_events -gt 0 ]]; then
            log "CRITICAL: $oom_events OOMKilled events detected!"
            kubectl --context "kind-$NAMESPACE" get events -n ${NAMESPACE} --field-selector reason=OOMKilling >> "${LOG_DIR}/oom-events.log"
        fi
    else
        log "⚠️   Unable to retrieve pod metrics"
    fi
    
    sleep 5  # Check every 5 seconds
done