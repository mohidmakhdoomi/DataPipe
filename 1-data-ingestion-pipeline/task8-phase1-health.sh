#!/bin/bash
# Task 8 Phase 1: Service Health Validation
# Based on Opus's execution strategy and Kimi's error handling guidance

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/../logs/data-ingestion-pipeline/task8-logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Phase 1: $*" | tee -a "${LOG_DIR}/phase1.log"
}

# Health check with retries
health_check() {
    local component=$1
    local retries=3
    local wait_seconds=10
    
    log "Checking health of $component..."
    
    for i in $(seq 1 $retries); do
        if kubectl --context "kind-$NAMESPACE" get pods -n ${NAMESPACE} -l app=$component --no-headers | grep -q "Running"; then
            local ready_count=$(kubectl --context "kind-$NAMESPACE" get pods -n ${NAMESPACE} -l app=$component --no-headers | grep "Running" | wc -l)
            log "✅ $component health check passed - $ready_count pod(s) running"
            return 0
        fi
        log "⚠️  $component health check attempt $i failed, waiting ${wait_seconds}s..."
        sleep $wait_seconds
    done
    
    log "❌ $component health check failed after $retries attempts"
    kubectl --context "kind-$NAMESPACE" describe pods -n ${NAMESPACE} -l app=$component >> "${LOG_DIR}/health-failure-$component.log"
    return 1
}

# Wait for deployment readiness
wait_for_deployment() {
    local deployment=$1
    local timeout=120
    
    log "Waiting for deployment $deployment to be ready..."
    if kubectl --context "kind-$NAMESPACE" wait --for=condition=available --timeout=${timeout}s deployment/$deployment -n ${NAMESPACE} 2>/dev/null; then
        log "✅ Deployment $deployment is ready"
        return 0
    else
        log "❌ Deployment $deployment failed to become ready within ${timeout}s"
        return 1
    fi
}

main() {
    log "=== Starting Phase 1: Service Health Validation ==="
    
    # Check namespace exists
    if ! kubectl --context "kind-$NAMESPACE" get namespace ${NAMESPACE} >/dev/null 2>&1; then
        log "❌ Namespace ${NAMESPACE} not found"
        return 1
    fi
    
    # Get all pods status
    log "Current pod status:"
    kubectl --context "kind-$NAMESPACE" get pods -n ${NAMESPACE} -o wide | tee -a "${LOG_DIR}/phase1.log"
    
    # Check individual components
    local components=("postgresql" "kafka" "schema-registry" "kafka-connect")
    local failed_components=()
    
    for component in "${components[@]}"; do
        if ! health_check "$component"; then
            failed_components+=("$component")
        fi
    done
    
    # Check services
    log "Checking service endpoints..."
    kubectl --context "kind-$NAMESPACE" get svc -n ${NAMESPACE} | tee -a "${LOG_DIR}/phase1.log"
    
    # Wait for all deployments to be ready
    local deployments=$(kubectl --context "kind-$NAMESPACE" get deployments -n ${NAMESPACE} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    for deployment in $deployments; do
        if ! wait_for_deployment "$deployment"; then
            failed_components+=("deployment-$deployment")
        fi
    done
    
    # Final health assessment
    if [[ ${#failed_components[@]} -eq 0 ]]; then
        log "✅ Phase 1 completed successfully - all services healthy"
        
        # Verify stable for 2 minutes
        log "Verifying stability for 2 minutes..."
        sleep 120
        
        # Final check
        local final_unhealthy=$(kubectl --context "kind-$NAMESPACE" get pods -n ${NAMESPACE} --no-headers | grep -v "Running\|Completed" | wc -l)
        if [[ $final_unhealthy -eq 0 ]]; then
            log "✅ All services remain stable - Phase 1 PASSED"
            return 0
        else
            log "❌ $final_unhealthy pod(s) became unhealthy during stability check"
            return 1
        fi
    else
        log "❌ Phase 1 failed - unhealthy components: ${failed_components[*]}"
        return 1
    fi
}

main "$@"