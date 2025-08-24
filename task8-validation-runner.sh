#!/bin/bash
# Task 8 Validation Runner - Main orchestrator script
# Based on consensus analysis and expert guidance from Kimi, Gemini, and Opus

set -euo pipefail  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Safer word splitting

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${SCRIPT_DIR}/task8-logs"
readonly MAX_MEMORY_MI=3584  # 3.5Gi in Mi (leaves 512Mi buffer)
readonly TIMEOUT=600         # 10 min per phase
readonly NAMESPACE="data-ingestion"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging function with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/validation.log"
}

# Install metrics-server if available
check_metrics_server() {
    log "Checking if metrics-server is available..."
    
    if kubectl top nodes >/dev/null 2>&1; then
        log "✅ Metrics-server is available"
        return 0
    else
        log "❌ Metrics-server is not available"
        return 1
    fi
}

# Memory check function
check_memory() {
    local current_mem=$(kubectl top pods -n ${NAMESPACE} --no-headers 2>/dev/null | awk '{sum+=$3+0} END {print sum}' || echo "0")
    log "Current memory usage: ${current_mem}Mi / 4096Mi $(($current_mem*100/4096))%"
    
    if [[ ${current_mem:-0} -gt ${MAX_MEMORY_MI} ]]; then
        log "WARNING: Memory usage critical - ${current_mem}Mi exceeds ${MAX_MEMORY_MI}Mi threshold"
        return 1
    fi
    return 0
}

# Phase execution wrapper
execute_phase() {
    local phase_num=$1
    local phase_name=$2
    local phase_script=$3
    
    log "=== Starting Phase ${phase_num}: ${phase_name} ==="
    
    # Pre-phase checks
    check_memory || {
        log "ERROR: Memory check failed before Phase ${phase_num}"
        return 1
    }
    
    # Capture pre-phase state
    kubectl get pods -n ${NAMESPACE} > "${LOG_DIR}/pre-phase-${phase_num}-pods.txt"
    
    # Execute phase
    local start_time=$(date +%s)
    if timeout ${TIMEOUT} bash "${phase_script}"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "Phase ${phase_num} completed successfully in ${duration} seconds"
        
        # Post-phase checks
        check_memory || {
            log "ERROR: Memory check failed after Phase ${phase_num}"
            return 1
        }

        # Post-phase stabilization
        sleep $((phase_num * 5))  # Progressive delay: 5s, 10s, 15s...
        return 0
    else
        log "ERROR: Phase ${phase_num} failed"
        kubectl describe pods -n ${NAMESPACE} >> "${LOG_DIR}/phase-${phase_num}-failure.log"
        return 1
    fi
}

# Main execution
main() {
    log "Starting Task 8 Validation - Data Ingestion Pipeline"
    log "Target: 1000 events/sec, <500ms latency, <3.8Gi memory usage"
    
    # Verify prerequisites
    if ! kubectl get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "ERROR: Namespace ${NAMESPACE} not found"
        exit 1
    fi

    if ! check_metrics_server; then
        log "ERROR: metrics-server not available"
        exit 1
    fi
    
    # Start background memory monitoring
    bash "${SCRIPT_DIR}/task8-memory-monitor.sh" &
    local monitor_pid=$!
    
    # Execute phases sequentially
    local phases=(
        "1:Service Health Validation:task8-phase1-health.sh"
        "2:Inter-Service Connectivity:task8-phase2-connectivity.sh"
        "3:CDC Pipeline Testing:task8-phase3-cdc-pipeline.sh"
        "4:Resource Monitoring:task8-phase4-resource-monitoring.sh"
        "5:Performance Benchmarking:task8-phase5-performance.sh"
        "6:Persistence Validation:task8-phase6-persistence.sh"
    )
    
    local failed_phases=()
    
    for phase_info in "${phases[@]}"; do
        IFS=':' read -r phase_num phase_name phase_script <<< "$phase_info"
        
        if ! execute_phase "$phase_num" "$phase_name" "${SCRIPT_DIR}/${phase_script}"; then
            failed_phases+=("Phase ${phase_num}: ${phase_name}")
            log "Phase ${phase_num} failed - stopping execution"
            break
        fi
    done
    
    # Stop memory monitoring
    kill $monitor_pid 2>/dev/null || true
    
    # Generate final report
    generate_report "${failed_phases[@]}"
    
    if [[ ${#failed_phases[@]} -eq 0 ]]; then
        log "✅ Task 8 Validation COMPLETED SUCCESSFULLY"
        update_task_status "completed"
        exit 0
    else
        log "❌ Task 8 Validation FAILED - ${#failed_phases[@]} phase(s) failed"
        exit 1
    fi
}

# Generate validation report
generate_report() {
    local failed_phases=("$@")
    local report_file="${LOG_DIR}/task8-validation-report.md"
    
    cat > "$report_file" << EOF
# Task 8 Validation Report

## Executive Summary
- Start Time: $(head -1 "${LOG_DIR}/validation.log" | cut -d']' -f1 | tr -d '[')
- End Time: $(date '+%Y-%m-%d %H:%M:%S')
- Overall Status: $([ ${#failed_phases[@]} -eq 0 ] && echo "✅ PASS" || echo "❌ FAIL")
- Failed Phases: ${#failed_phases[@]}

## Failed Phases
$(printf '%s\n' "${failed_phases[@]}")

## Resource Utilization
$(tail -10 "${LOG_DIR}/memory-monitor.log" 2>/dev/null || echo "Memory monitoring data not available")

## Next Steps
$([ ${#failed_phases[@]} -eq 0 ] && echo "Ready to proceed to Phase 3 integration tasks" || echo "Address failed phases before proceeding")

## Logs Location
All detailed logs available in: ${LOG_DIR}/
EOF
    
    log "Validation report generated: $report_file"
}

# Update task status in tasks.md
update_task_status() {
    local status=$1
    local tasks_file=".kiro/specs/data-ingestion-pipeline/tasks.md"
    
    if [[ -f "$tasks_file" ]]; then
        # Update Task 8 status
        sed -i 's/- \[ \] 8\. Validate core services connectivity and performance/- [x] 8. Validate core services connectivity and performance/' "$tasks_file"
        log "Updated task status in $tasks_file"
    fi
}

# Execute main function
main "$@"