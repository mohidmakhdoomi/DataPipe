#!/bin/bash
# Task 8 Phase 2: Inter-Service Connectivity Testing
# Based on Kimi's connectivity testing with exponential backoff

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/../logs/data-ingestion-pipeline/task8-logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Phase 2: $*" | tee -a "${LOG_DIR}/phase2.log"
}

# Connectivity check with exponential backoff
connectivity_check() {
    local service=$1
    local port=$2
    local max_attempts=5
    local backoff=2
    
    log "Testing connectivity to $service:$port..."
    
    for i in $(seq 1 $max_attempts); do
        # Use a temporary pod for connectivity testing
        # Test from kafka-connect pod, as it needs to connect to all other services
        if kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- sh -c "nc -z -w 5 $service.$NAMESPACE.svc.cluster.local $port" >/dev/null 2>&1; then
            log "✅ Connectivity to $service:$port confirmed"
            return 0
        fi
        
        local wait_time=$((backoff ** (i-1)))
        log "⚠️  Connectivity to $service:$port failed (attempt $i), waiting ${wait_time}s..."
        sleep $wait_time
    done
    
    log "❌ Cannot reach $service:$port after $max_attempts attempts"
    return 1
}

# Test specific service endpoints
test_postgresql() {
    log "Testing PostgreSQL connectivity..."
    
    # Test basic connection
    if kubectl exec -n ${NAMESPACE} postgresql-0 -- pg_isready -U postgres -d ecommerce >/dev/null 2>&1; then
        log "✅ PostgreSQL is ready and accepting connections"
        
        # Test database query
        if kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -d ecommerce -c "SELECT version();" >/dev/null 2>&1; then
            log "✅ PostgreSQL query execution successful"
            return 0
        else
            log "❌ PostgreSQL query execution failed"
            return 1
        fi
    else
        log "❌ PostgreSQL is not ready"
        return 1
    fi
}

test_schema_registry() {
    log "Testing Schema Registry connectivity..."
    
    if kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- curl -s http://schema-registry.${NAMESPACE}.svc.cluster.local:8081/subjects >/dev/null 2>&1; then
        log "✅ Schema Registry REST API accessible"
        return 0
    else
        log "❌ Schema Registry REST API not accessible"
        return 1
    fi
}

test_kafka() {
    log "Testing Kafka connectivity..."
    
    # Test broker API
    if kubectl exec -n ${NAMESPACE} kafka-0 -- kafka-broker-api-versions \
       --bootstrap-server localhost:9092 >/dev/null 2>&1; then
        log "✅ Kafka broker API accessible"
        
        # Test topic listing
        if kubectl exec -n ${NAMESPACE} kafka-0 -- kafka-topics \
           --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
            log "✅ Kafka topic listing successful"
            return 0
        else
            log "❌ Kafka topic listing failed"
            return 1
        fi
    else
        log "❌ Kafka broker API not accessible"
        return 1
    fi
}

test_kafka_connect() {
    log "Testing Kafka Connect connectivity..."
    
    # Test REST API endpoint from within the pod
    if kubectl exec -n ${NAMESPACE} deploy/kafka-connect -- curl -f -s http://localhost:8083/connectors >/dev/null 2>&1; then
        log "✅ Kafka Connect REST API accessible"
        return 0
    else
        log "❌ Kafka Connect REST API not accessible"
        return 1
    fi
}

main() {
    log "=== Starting Phase 2: Inter-Service Connectivity Testing ==="
    
    # Basic network connectivity tests
    local services=(
        "postgresql:5432"
        "kafka:9092"
        "schema-registry:8081"
        "kafka-connect:8083"
    )
    
    local failed_connections=()
    
    for service_port in "${services[@]}"; do
        IFS=':' read -r service port <<< "$service_port"
        if ! connectivity_check "$service" "$port"; then
            failed_connections+=("$service:$port")
        fi
    done
    
    # Service-specific functionality tests
    local service_tests=("test_postgresql" "test_kafka" "test_schema_registry" "test_kafka_connect")
    local failed_services=()
    
    for test_func in "${service_tests[@]}"; do
        if ! $test_func; then
            failed_services+=("${test_func#test_}")
        fi
    done
    
    # DNS resolution test
    log "Testing DNS resolution from postgresql-0 pod..."
    if kubectl exec -n ${NAMESPACE} postgresql-0 -- nslookup kafka.${NAMESPACE}.svc.cluster.local >/dev/null 2>&1; then
        log "✅ DNS resolution working"
    else
        log "❌ DNS resolution failed"
        failed_connections+=("dns-resolution")
    fi
    
    # Final assessment
    local total_failures=$((${#failed_connections[@]} + ${#failed_services[@]}))
    
    if [[ $total_failures -eq 0 ]]; then
        log "✅ Phase 2 completed successfully - all connectivity tests passed"
        return 0
    else
        log "❌ Phase 2 failed - $total_failures connectivity issue(s)"
        [[ ${#failed_connections[@]} -gt 0 ]] && log "Failed connections: ${failed_connections[*]}"
        [[ ${#failed_services[@]} -gt 0 ]] && log "Failed services: ${failed_services[*]}"
        return 1
    fi
}

main "$@"
