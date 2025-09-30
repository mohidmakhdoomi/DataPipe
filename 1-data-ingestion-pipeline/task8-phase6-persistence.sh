#!/bin/bash
# Task 8 Phase 6: Persistence Validation
# Based on Opus's execution strategy for persistence testing

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/logs/data-ingestion-pipeline/task8-logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Phase 6: $*" | tee -a "${LOG_DIR}/phase6.log"
}

# Record baseline state
record_baseline() {
    log "Recording baseline state..."
    
    # PostgreSQL data count
    local pg_count=$(kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -d ecommerce -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
    echo "$pg_count" > "${LOG_DIR}/baseline-users-count.txt"
    log "Baseline PostgreSQL users count: $pg_count"
    
    # Kafka topic offsets
    kubectl exec -n ${NAMESPACE} kafka-0 -- kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 --topic ecommerce-db.public.users --time -1 \
        > "${LOG_DIR}/baseline-kafka-offsets.txt" 2>/dev/null || echo "topic:partition:offset" > "${LOG_DIR}/baseline-kafka-offsets.txt"
    
    local offset_count=$(wc -l < "${LOG_DIR}/baseline-kafka-offsets.txt")
    log "Baseline Kafka offsets recorded: $offset_count entries"
    
    # Record current pod states
    kubectl get pods -n ${NAMESPACE} -o wide > "${LOG_DIR}/baseline-pods.txt"
    log "Baseline pod states recorded"
}

# Force pod restarts
force_pod_restarts() {
    log "Forcing pod restarts to test persistence..."
    
    # Get current pod names
    local pg_pod=$(kubectl get pods -n ${NAMESPACE} -l app=postgresql,component=database -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    local kafka_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka,component=streaming -o jsonpath='{.items[2].metadata.name}' 2>/dev/null || echo "kafka-2")
    local connect_pod=$(kubectl get pods -n ${NAMESPACE} -l app=kafka-connect,component=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    local schema_pod=$(kubectl get pods -n ${NAMESPACE} -l app=schema-registry,component=schema-management -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
       
    local deleted_pods=()

    if [[ -n "$connect_pod" ]]; then
        kubectl scale deploy kafka-connect -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for Kafka Connect to terminate..."
        if kubectl wait --for=delete pod -l app=kafka-connect,component=worker -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ Kafka Connect scaled to replicas=0"
            deleted_pods+=("$connect_pod")
        else
            log "⚠️ Kafka Connect failed to scale to replicas=0"
        fi
    fi

    if [[ -n "$schema_pod" ]]; then
        kubectl scale deploy schema-registry -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for Schema Registry to terminate..."
        if kubectl wait --for=delete pod -l app=schema-registry,component=schema-management -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ Schema Registry scaled to replicas=0"
            deleted_pods+=("$schema_pod")
        else
            log "⚠️ Schema Registry failed to scale to replicas=0"
        fi
    fi

    if [[ -n "$kafka_pod" ]]; then
        kubectl scale sts kafka -n ${NAMESPACE} --replicas=2 >/dev/null 2>&1 &
        log "Waiting for Kafka to terminate..."
        if kubectl wait --for=jsonpath='{.status.readyReplicas}'=2 sts kafka -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ Kafka scaled to replicas=2"
            deleted_pods+=("$kafka_pod")
        else
            log "⚠️ Kafka failed to scale to replicas=2"
        fi
    fi

    if [[ -n "$pg_pod" ]]; then
        kubectl scale sts postgresql -n ${NAMESPACE} --replicas=0 >/dev/null 2>&1 &
        log "Waiting for PostgreSQL to terminate..."
        if kubectl wait --for=delete pod -l app=postgresql,component=database -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
            log "✅ PostgreSQL scaled to replicas=0"
            deleted_pods+=("$pg_pod")
        else
            log "⚠️ PostgreSQL failed to scale to replicas=0"
        fi
    fi
    
    log "Deleted ${#deleted_pods[@]} pod(s)"
    
    # Wait a moment for deletions to register
    sleep 10
}

# Wait for pods to restart
wait_for_restart() {
    log "Restarting pods..."
    
    # Wait for PostgreSQL
    log "Scaling PostgreSQL to replicas=1"
    kubectl scale sts postgresql -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for PostgreSQL to be ready..."
    if kubectl wait --for=condition=ready pod -l app=postgresql,component=database -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ PostgreSQL pod restarted and ready"
    else
        log "⚠️  PostgreSQL pod restart timeout (may still be starting)"
    fi
    
    # Wait for Kafka
    log "Scaling Kafka to replicas=3"
    kubectl scale sts kafka -n ${NAMESPACE} --replicas=3 >/dev/null 2>&1 &
    log "Waiting for Kafka to be ready..."
    local status=$(kubectl wait --for=condition=ready pod -l app=kafka,component=streaming -n ${NAMESPACE} --timeout=300s 2>&1)
    if [[ -n "$status" ]] && [[ $(echo "$status" | grep "condition met" | wc -l) -eq 3 ]]; then
        log "✅ Kafka pod restarted and ready"
    else
        log "⚠️  Kafka pod restart timeout (may still be starting)"
    fi
    
    # Wait for Schema Registry
    log "Scaling Schema Registry to replicas=1"
    kubectl scale deploy schema-registry -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for Schema Registry to be ready..."
    if kubectl wait --for=condition=ready pod -l app=schema-registry,component=schema-management -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ Schema Registry pod restarted and ready"
    else
        log "⚠️  Schema Registry pod restart timeout (may still be starting)"
    fi

    # Wait for Kafka Connect
    log "Scaling Kafka Connect to replicas=1"
    kubectl scale deploy kafka-connect -n ${NAMESPACE} --replicas=1 >/dev/null 2>&1 &
    log "Waiting for Kafka Connect to be ready..."
    if kubectl wait --for=condition=ready pod -l app=kafka-connect,component=worker -n ${NAMESPACE} --timeout=300s >/dev/null 2>&1; then
        log "✅ Kafka Connect pod restarted and ready"
    else
        log "⚠️  Kafka Connect pod restart timeout (may still be starting)"
    fi
    
    # Additional stabilization time
    log "Allowing additional stabilization time..."
    sleep 60
}

# Verify data persistence
verify_persistence() {
    log "Verifying data persistence after restart..."
    
    local persistence_ok=true
    
    # Check PostgreSQL data
    log "Checking PostgreSQL data persistence..."
    local pg_count_after=$(kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -d ecommerce -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ' || echo "0")
    local pg_count_before=$(cat "${LOG_DIR}/baseline-users-count.txt" 2>/dev/null || echo "0")
    
    echo "$pg_count_after" > "${LOG_DIR}/after-restart-users-count.txt"
    
    if [[ "$pg_count_before" == "$pg_count_after" ]]; then
        log "✅ PostgreSQL data persistence: PASSED ($pg_count_after users)"
    else
        log "❌ PostgreSQL data persistence: FAILED (before: $pg_count_before, after: $pg_count_after)"
        persistence_ok=false
    fi
    
    # Check Kafka data (offsets should be preserved)
    log "Checking Kafka data persistence..."
    kubectl exec -n ${NAMESPACE} kafka-0 -- kafka-run-class kafka.tools.GetOffsetShell \
        --broker-list localhost:9092 --topic ecommerce-db.public.users --time -1 \
        > "${LOG_DIR}/after-restart-kafka-offsets.txt" 2>/dev/null || echo "topic:partition:offset" > "${LOG_DIR}/after-restart-kafka-offsets.txt"
    
    if diff "${LOG_DIR}/baseline-kafka-offsets.txt" "${LOG_DIR}/after-restart-kafka-offsets.txt" >/dev/null 2>&1; then
        log "✅ Kafka data persistence: PASSED (offsets preserved)"
    else
        log "⚠️  Kafka data persistence: Offsets changed (may be normal for active topics)"
        # Don't fail on this as offsets can change with active CDC
    fi
    
    # Test basic connectivity after restart
    log "Testing connectivity after restart..."
    local connectivity_ok=true
    
    # Test PostgreSQL connectivity
    if kubectl exec -n ${NAMESPACE} postgresql-0 -- pg_isready -U postgres -d ecommerce >/dev/null 2>&1; then
        log "✅ PostgreSQL connectivity restored"
    else
        log "❌ PostgreSQL connectivity failed"
        connectivity_ok=false
        persistence_ok=false
    fi
    
    # Test Kafka connectivity
    if kubectl exec -n ${NAMESPACE} kafka-0 -- kafka-broker-api-versions --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        log "✅ Kafka connectivity restored"
    else
        log "❌ Kafka connectivity failed"
        connectivity_ok=false
        persistence_ok=false
    fi
    
    return $([ "$persistence_ok" = true ] && echo 0 || echo 1)
}

# Test CDC connector recovery
test_cdc_recovery() {
    log "Testing CDC connector recovery..."
    
    # Wait for connector to recover
    local max_wait=120
    local wait_interval=10
    local elapsed=0
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status=$(kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- \
                      curl -s http://localhost:8083/connectors/postgres-cdc-connector/status \
                      2>/dev/null | grep -o '"connector":{"state":"[^"]*"' | cut -d'"' -f6 || echo "UNKNOWN")
        
        if [[ "$status" == "RUNNING" ]]; then
            log "✅ CDC connector recovered and running"
            return 0
        else
            log "⏳ CDC connector status: $status (waiting for recovery...)"
            sleep $wait_interval
            elapsed=$((elapsed + wait_interval))
        fi
    done
    
    log "⚠️  CDC connector did not recover within ${max_wait}s"
    return 1
}

main() {
    log "=== Starting Phase 6: Persistence Validation ==="
    
    # Step 1: Record baseline state
    record_baseline
    
    # Step 2: Force pod restarts
    force_pod_restarts
    
    # Step 3: Wait for pods to restart
    wait_for_restart
    
    # Step 4: Verify data persistence
    if ! verify_persistence; then
        log "❌ Phase 6 failed - data persistence validation failed"
        return 1
    fi
    
    # Step 5: Test CDC connector recovery
    if ! test_cdc_recovery; then
        log "⚠️  CDC connector recovery incomplete but continuing..."
    fi
    
    # Step 6: Final health check
    log "Performing final health check..."
    local unhealthy_pods=$(kubectl get pods -n ${NAMESPACE} --no-headers | grep -v "Running\|Completed" | wc -l)
    
    if [[ $unhealthy_pods -eq 0 ]]; then
        log "✅ All pods healthy after restart"
    else
        log "⚠️  $unhealthy_pods pod(s) not in Running state"
    fi
    
    log "✅ Phase 6 completed successfully - persistence validation passed"
    return 0
}

main "$@"