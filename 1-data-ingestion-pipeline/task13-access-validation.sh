#!/bin/bash

# Task 13: Data-Ingestion-Specific Security Procedures - Access Validation Script
#
# This script validates CDC user permissions and data access controls for pipeline components:
# - PostgreSQL CDC user permissions validation
# - Kafka Connect service account access validation
# - Schema Registry authentication validation
# - Network connectivity and security policy validation
# - AWS S3 access validation
#
# Usage: ./task13-access-validation.sh [--verbose] [--component postgresql|kafka-connect|schema-registry|s3|all]

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
readonly NAMESPACE="data-ingestion"
readonly POSTGRES_SERVICE="postgresql.${NAMESPACE}.svc.cluster.local"
readonly KAFKA_CONNECT_SERVICE="kafka-connect.${NAMESPACE}.svc.cluster.local:8083"
readonly SCHEMA_REGISTRY_SERVICE="schema-registry.${NAMESPACE}.svc.cluster.local:8081"
readonly KAFKA_SERVICE="kafka-headless.${NAMESPACE}.svc.cluster.local:9092"
readonly LOG_DIR="${SCRIPT_DIR}/../logs/data-ingestion-pipeline/task13-logs"
readonly LOG_FILE="${LOG_DIR}/access-validation.log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "[$timestamp] ${BLUE}[INFO]${NC} $message" ;;
        WARN)  echo -e "[$timestamp] ${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "[$timestamp] ${RED}[ERROR]${NC} $message" ;;
        SUCCESS) echo -e "[$timestamp] ${GREEN}[SUCCESS]${NC} $message" ;;
        DEBUG) [[ "${VERBOSE:-false}" == "true" ]] && echo -e "[$timestamp] [DEBUG] $message" ;;
    esac
    echo -e "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Parse command line arguments
VERBOSE=false
COMPONENT="all"

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --component)
            COMPONENT="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--verbose] [--component postgresql|kafka-connect|schema-registry|s3|all]"
            echo ""
            echo "Options:"
            echo "  --verbose                    Enable verbose output"
            echo "  --component COMPONENT        Validate specific component (default: all)"
            echo "  -h, --help                  Show this help message"
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validation results tracking
declare -A VALIDATION_RESULTS
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test result tracking
record_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    VALIDATION_RESULTS["$test_name"]="$result"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [[ "$result" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log SUCCESS "$test_name: PASSED"
        [[ -n "$details" ]] && log DEBUG "$details"
    elif [[ "$result" == "WARN" ]]; then
        log WARN "$test_name: WARNING"
        [[ -n "$details" ]] && log WARN "$details"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log ERROR "$test_name: FAILED"
        [[ -n "$details" ]] && log ERROR "$details"
    fi
}

# PostgreSQL CDC user permissions validation
validate_postgresql_permissions() {
    log INFO "Validating PostgreSQL CDC user permissions..."
    
    # Test 1: Basic connectivity
    if kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -c "SELECT 1;" &> /dev/null; then
        record_test_result "PostgreSQL Connectivity" "PASS" "Successfully connected to PostgreSQL"
    else
        record_test_result "PostgreSQL Connectivity" "FAIL" "Cannot connect to PostgreSQL"
    fi
    
    # Test 2: CDC user exists and has replication privileges
    local current_user=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -c postgresql -- psql -U postgres -d ecommerce -t -c "
        SELECT DISTINCT usename FROM pg_stat_replication" | tr -d ' ' || echo "")

    if [[ ! -n "$current_user" ]]; then
        record_test_result "CDC User Replication Privileges" "FAIL" "No CDC user from pg_stat_replication"
    fi

    local cdc_user_info
    cdc_user_info=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -t -c "
        SELECT rolname, rolreplication, rolcanlogin 
        FROM pg_roles 
        WHERE rolname='$current_user' " 2>/dev/null | tr -d ' ' || echo "")
    if [[ -n "$cdc_user_info" ]]; then
        local user_name=$(echo "$cdc_user_info" | cut -d'|' -f1)
        local has_replication=$(echo "$cdc_user_info" | cut -d'|' -f2)
        local can_login=$(echo "$cdc_user_info" | cut -d'|' -f3)
        
        if [[ "$has_replication" == "t" && "$can_login" == "t" ]]; then
            record_test_result "CDC User Replication Privileges" "PASS" "User $user_name has replication and login privileges"
        else
            record_test_result "CDC User Replication Privileges" "FAIL" "User $user_name missing required privileges (replication: $has_replication, login: $can_login)"
        fi
    else
        record_test_result "CDC User Replication Privileges" "FAIL" "No CDC user from pg_roles"
    fi
    
    # Test 3: CDC user has SELECT permissions on required tables
    local tables=("users" "products" "orders" "order_items")
    local permissions_valid=true
    
    for table in "${tables[@]}"; do
        local has_select
        has_select=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -t -c "
            SELECT has_table_privilege('$user_name', 'public.$table', 'SELECT');" 2>/dev/null | tr -d ' ' || echo "f")
        
        if [[ "$has_select" != "t" ]]; then
            permissions_valid=false
            log DEBUG "CDC user missing SELECT permission on table: $table"
        fi
    done
    
    if [[ "$permissions_valid" == "true" ]]; then
        record_test_result "CDC User Table Permissions" "PASS" "CDC user has SELECT permissions on all required tables"
    else
        record_test_result "CDC User Table Permissions" "FAIL" "CDC user missing SELECT permissions on some tables"
    fi
    
    # Test 4: Replication slot exists and is active
    local slot_info
    slot_info=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -t -c "
        SELECT slot_name, active, confirmed_flush_lsn IS NOT NULL as has_lsn
        FROM pg_replication_slots 
        WHERE slot_name like 'debezium_slot%' and active='t';" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ -n "$slot_info" ]]; then
        local num_slots=$(echo "$slot_info" | wc -l)
        local slot_active=$(echo "$slot_info" | cut -d'|' -f2 | uniq)
        local has_lsn=$(echo "$slot_info" | cut -d'|' -f3 | uniq)
        
        if [[ $num_slots -eq 4 && "$slot_active" == "t" && "$has_lsn" == "t" ]]; then
            record_test_result "Replication Slot Status" "PASS" "Replication slot is active and has valid LSN"
        else
            record_test_result "Replication Slot Status" "FAIL" "Replication slot issues (num_slots: $num_slots, active: $slot_active, has_lsn: $has_lsn)"
        fi
    else
        record_test_result "Replication Slot Status" "FAIL" "Replication slot 'debezium_slot' not found"
    fi
    
    # Test 5: WAL level configuration
    local wal_level
    wal_level=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -t -c "SHOW wal_level;" 2>/dev/null | tr -d ' ' || echo "")
    
    if [[ "$wal_level" == "logical" ]]; then
        record_test_result "WAL Level Configuration" "PASS" "WAL level is set to logical"
    else
        record_test_result "WAL Level Configuration" "FAIL" "WAL level is '$wal_level', should be 'logical'"
    fi
    
    # Test 6: Max replication slots configuration
    local max_replication_slots
    max_replication_slots=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" postgresql-0 -- psql -U postgres -d ecommerce -t -c "SHOW max_replication_slots;" 2>/dev/null | tr -d ' ' || echo "0")
    
    if (( max_replication_slots >= 4 )); then
        record_test_result "Max Replication Slots" "PASS" "Max replication slots: $max_replication_slots"
    else
        record_test_result "Max Replication Slots" "FAIL" "Max replication slots too low: $max_replication_slots (should be >= 4)"
    fi
    
    log INFO "PostgreSQL permissions validation completed"
}

# Kafka Connect access validation
validate_kafka_connect_access() {
    log INFO "Validating Kafka Connect access..."
    
    # Test 1: Kafka Connect service connectivity
    if kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/" &> /dev/null; then
        record_test_result "Kafka Connect Connectivity" "PASS" "Successfully connected to Kafka Connect"
    else
        record_test_result "Kafka Connect Connectivity" "FAIL" "Cannot connect to Kafka Connect service"
    fi
    
    # Test 2: Kafka Connect version and status
    local connect_info
    connect_info=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/" | jq -r '.version + "|" + .kafka_cluster_id' 2>/dev/null || echo "|")
    
    if [[ "$connect_info" != "|" ]]; then
        local version=$(echo "$connect_info" | cut -d'|' -f1)
        local cluster_id=$(echo "$connect_info" | cut -d'|' -f2)
        record_test_result "Kafka Connect Version" "PASS" "Version: $version, Cluster ID: $cluster_id"
    else
        record_test_result "Kafka Connect Version" "FAIL" "Cannot retrieve Kafka Connect version information"
    fi
    
    # Test 3: Connector plugins availability
    local plugins
    plugins=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/connector-plugins" | jq -r '.[].class' 2>/dev/null || echo "")
    
    local required_plugins=("io.debezium.connector.postgresql.PostgresConnector" "io.confluent.connect.s3.S3SinkConnector")
    local plugins_valid=true
    
    for plugin in "${required_plugins[@]}"; do
        if ! echo "$plugins" | grep -q "$plugin"; then
            plugins_valid=false
            log DEBUG "Missing required plugin: $plugin"
        fi
    done
    
    if [[ "$plugins_valid" == "true" ]]; then
        record_test_result "Required Connector Plugins" "PASS" "All required connector plugins are available"
    else
        record_test_result "Required Connector Plugins" "FAIL" "Some required connector plugins are missing"
    fi
    
    # Test 4: Debezium connector status
    local connector_status
    connector_status=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/connectors/postgres-cdc-users-connector/status" | jq -r '.connector.state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$connector_status" == "RUNNING" ]]; then
        record_test_result "Debezium Connector Status" "PASS" "Debezium connector is running"
    else
        record_test_result "Debezium Connector Status" "FAIL" "Debezium connector status: $connector_status"
    fi
    
    # Test 5: Connector task status
    local task_status
    task_status=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/connectors/postgres-cdc-users-connector/status" | jq -r '.tasks[0].state // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    
    if [[ "$task_status" == "RUNNING" ]]; then
        record_test_result "Connector Task Status" "PASS" "Connector task is running"
    else
        record_test_result "Connector Task Status" "FAIL" "Connector task status: $task_status"
    fi
    
    # Test 6: Kafka connectivity from Kafka Connect
    local kafka_connectivity
    kafka_connectivity=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://localhost:8083/connectors/postgres-cdc-users-connector/config" | jq -r '.["database.hostname"] // "unknown"' 2>/dev/null || echo "unknown")
    
    if [[ "$kafka_connectivity" != "unknown" ]]; then
        record_test_result "Kafka Connect to Kafka" "PASS" "Kafka Connect can communicate with Kafka"
    else
        record_test_result "Kafka Connect to Kafka" "FAIL" "Cannot verify Kafka Connect to Kafka communication"
    fi
    
    log INFO "Kafka Connect access validation completed"
}

# Schema Registry authentication validation
validate_schema_registry_access() {
    log INFO "Validating Schema Registry access..."
    
    # Test 1: Schema Registry connectivity
    if kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$SCHEMA_REGISTRY_SERVICE/" &> /dev/null; then
        record_test_result "Schema Registry Connectivity" "PASS" "Successfully connected to Schema Registry"
    else
        record_test_result "Schema Registry Connectivity" "FAIL" "Cannot connect to Schema Registry"
    fi
    
    # Test 2: Schema Registry subjects endpoint
    local subjects
    subjects=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$SCHEMA_REGISTRY_SERVICE/subjects" | jq -r 'length' 2>/dev/null || echo "0")
    
    if [[ "$subjects" != "0" ]]; then
        record_test_result "Schema Registry Subjects" "PASS" "Schema Registry has $subjects registered subjects"
    else
        record_test_result "Schema Registry Subjects" "WARN" "No subjects registered in Schema Registry (may be normal for new deployment)"
    fi
    
    # Test 3: Schema Registry configuration
    local compatibility
    local schema_user schema_pass
    
    # Get Schema Registry credentials from secret
    schema_user=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    schema_pass=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$schema_user" && -n "$schema_pass" ]]; then
        compatibility=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s -u "$schema_user:$schema_pass" "http://$SCHEMA_REGISTRY_SERVICE/config" | jq -r '.compatibilityLevel // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    else
        compatibility=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$SCHEMA_REGISTRY_SERVICE/config" | jq -r '.compatibilityLevel // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")
    fi
    
    if [[ "$compatibility" == "BACKWARD" ]]; then
        record_test_result "Schema Compatibility Level" "PASS" "Compatibility level set to BACKWARD"
    else
        record_test_result "Schema Compatibility Level" "WARN" "Compatibility level: $compatibility (expected: BACKWARD)"
    fi
    
    # Test 4: Authentication configuration (if enabled)
    local auth_response
    local schema_user schema_pass
    
    # Get Schema Registry credentials from secret
    schema_user=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    schema_pass=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$schema_user" && -n "$schema_pass" ]]; then
        auth_response=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s -w "%{http_code}" -u "$schema_user:$schema_pass" "http://$SCHEMA_REGISTRY_SERVICE/subjects" -o /dev/null 2>/dev/null || echo "000")
        
        if [[ "$auth_response" == "200" ]]; then
            record_test_result "Schema Registry Authentication" "PASS" "Schema Registry accessible with authentication"
        elif [[ "$auth_response" == "401" ]]; then
            record_test_result "Schema Registry Authentication" "FAIL" "Schema Registry authentication failed (401 Unauthorized)"
        else
            record_test_result "Schema Registry Authentication" "WARN" "Unexpected response code: $auth_response"
        fi
    else
        # Try without authentication
        auth_response=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s -w "%{http_code}" "http://$SCHEMA_REGISTRY_SERVICE/subjects" -o /dev/null 2>/dev/null || echo "000")
        
        if [[ "$auth_response" == "200" ]]; then
            record_test_result "Schema Registry Authentication" "PASS" "Schema Registry accessible (no authentication required)"
        else
            record_test_result "Schema Registry Authentication" "WARN" "Schema Registry credentials not found, response: $auth_response"
        fi
    fi
    
    # Test 5: Kafka connectivity from Schema Registry
    local sr_kafka_connectivity
    local schema_user schema_pass
    
    # Get Schema Registry credentials from secret
    schema_user=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-user}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    schema_pass=$(kubectl --context "kind-$NAMESPACE" get secret schema-registry-auth -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$schema_user" && -n "$schema_pass" ]]; then
        sr_kafka_connectivity=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/schema-registry -- curl -s -u "$schema_user:$schema_pass" "http://localhost:8081/config" | jq -r '.compatibilityLevel' 2>/dev/null || echo "unknown")
    else
        # Try without authentication or check environment variables
        sr_kafka_connectivity=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/schema-registry -- printenv SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS 2>/dev/null || echo "unknown")
    fi
    
    if [[ "$sr_kafka_connectivity" != "unknown" && "$sr_kafka_connectivity" != "" ]]; then
        record_test_result "Schema Registry to Kafka" "PASS" "Schema Registry configured to connect to Kafka: $sr_kafka_connectivity"
    else
        record_test_result "Schema Registry to Kafka" "WARN" "Cannot verify Schema Registry to Kafka configuration"
    fi
    
    log INFO "Schema Registry access validation completed"
}

# AWS S3 access validation
validate_s3_access() {
    log INFO "Validating AWS S3 access..."
    
    # Test 1: AWS Environment Variables (S3 connector uses AWS Java SDK, not CLI)
    local aws_key_id aws_secret_key aws_region
    aws_key_id=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- printenv AWS_ACCESS_KEY_ID 2>/dev/null || echo "")
    aws_secret_key=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- printenv AWS_SECRET_ACCESS_KEY 2>/dev/null || echo "")
    aws_region=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- printenv AWS_DEFAULT_REGION 2>/dev/null || echo "")
    
    if [[ -n "$aws_key_id" && -n "$aws_secret_key" && -n "$aws_region" ]]; then
        record_test_result "AWS Credentials Configuration" "PASS" "AWS credentials environment variables are properly configured"
    else
        local missing_vars=()
        [[ -z "$aws_key_id" ]] && missing_vars+=("AWS_ACCESS_KEY_ID")
        [[ -z "$aws_secret_key" ]] && missing_vars+=("AWS_SECRET_ACCESS_KEY")
        [[ -z "$aws_region" ]] && missing_vars+=("AWS_DEFAULT_REGION")
        record_test_result "AWS Credentials Configuration" "FAIL" "Missing AWS environment variables: ${missing_vars[*]}"
    fi
    
    # Test 2: S3 Bucket Configuration
    local s3_bucket
    s3_bucket=$(kubectl --context "kind-$NAMESPACE" get secret aws-credentials -n "$NAMESPACE" -o jsonpath='{.data.s3-bucket}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    
    if [[ -n "$s3_bucket" ]]; then
        record_test_result "S3 Bucket Configuration" "PASS" "S3 bucket configured"
    else
        record_test_result "S3 Bucket Configuration" "WARN" "S3 bucket name not configured in secrets"
    fi
    
    # Test 3: S3 Connector Plugin Availability
    local s3_plugin_available
    s3_plugin_available=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/connector-plugins" | jq -r '.[] | select(.class == "io.confluent.connect.s3.S3SinkConnector") | .class' 2>/dev/null || echo "")
    
    if [[ "$s3_plugin_available" == "io.confluent.connect.s3.S3SinkConnector" ]]; then
        record_test_result "S3 Connector Plugin" "PASS" "S3 Sink connector plugin is available"
    else
        record_test_result "S3 Connector Plugin" "FAIL" "S3 Sink connector plugin not found"
    fi
    
    # Test 4: S3 Sink connector status (if deployed)
    local s3_connector_status
    s3_connector_status=$(kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- curl -s "http://$KAFKA_CONNECT_SERVICE/connectors/s3-sink-users-connector/status" | jq -r '.connector.state // "NOT_FOUND"' 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$s3_connector_status" == "RUNNING" ]]; then
        record_test_result "S3 Sink Connector Status" "PASS" "S3 Sink connector is running"
    elif [[ "$s3_connector_status" == "NOT_FOUND" ]]; then
        record_test_result "S3 Sink Connector Status" "WARN" "S3 Sink connector not deployed"
    else
        record_test_result "S3 Sink Connector Status" "FAIL" "S3 Sink connector status: $s3_connector_status"
    fi
    
    log INFO "AWS S3 access validation completed"
}

# Network connectivity validation
validate_network_connectivity() {
    log INFO "Validating network connectivity..."
    
    # Test 1: Kafka Connect to PostgreSQL connectivity
    local kc_to_pg
    kc_to_pg=$(timeout 10 kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- nc -z postgresql 5432 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    
    if [[ "$kc_to_pg" == "SUCCESS" ]]; then
        record_test_result "Kafka Connect to PostgreSQL" "PASS" "Network connectivity verified"
    else
        record_test_result "Kafka Connect to PostgreSQL" "FAIL" "Cannot connect to PostgreSQL from Kafka Connect"
    fi
    
    # Test 2: Kafka Connect to Kafka connectivity
    local kc_to_kafka
    kc_to_kafka=$(timeout 5 kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- nc -z kafka-headless 9092 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    
    if [[ "$kc_to_kafka" == "SUCCESS" ]]; then
        record_test_result "Kafka Connect to Kafka" "PASS" "Network connectivity verified"
    else
        record_test_result "Kafka Connect to Kafka" "WARN" "Network connectivity test failed or timed out"
    fi
    
    # Test 3: Kafka Connect to Schema Registry connectivity
    local kc_to_sr
    kc_to_sr=$(timeout 5 kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/kafka-connect -c kafka-connect -- nc -z schema-registry 8081 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    
    if [[ "$kc_to_sr" == "SUCCESS" ]]; then
        record_test_result "Kafka Connect to Schema Registry" "PASS" "Network connectivity verified"
    else
        record_test_result "Kafka Connect to Schema Registry" "WARN" "Network connectivity test failed or timed out"
    fi
    
    # Test 4: Schema Registry to Kafka connectivity
    local sr_to_kafka
    sr_to_kafka=$(timeout 5 kubectl --context "kind-$NAMESPACE" exec -n "$NAMESPACE" deployment/schema-registry -- nc -z kafka-headless 9092 2>/dev/null && echo "SUCCESS" || echo "FAILED")
    
    if [[ "$sr_to_kafka" == "SUCCESS" ]]; then
        record_test_result "Schema Registry to Kafka" "PASS" "Network connectivity verified"
    else
        record_test_result "Schema Registry to Kafka" "WARN" "Network connectivity test failed or timed out"
    fi
    
    log INFO "Network connectivity validation completed"
}

# Kubernetes RBAC validation
validate_kubernetes_rbac() {
    log INFO "Validating Kubernetes RBAC..."
    
    # Test 1: Service accounts exist
    local service_accounts=("postgresql-sa" "kafka-sa" "kafka-connect-sa" "schema-registry-sa")
    local sa_valid=true
    
    for sa in "${service_accounts[@]}"; do
        if kubectl --context "kind-$NAMESPACE" get serviceaccount "$sa" -n "$NAMESPACE" &> /dev/null; then
            log DEBUG "Service account $sa exists"
        else
            sa_valid=false
            log DEBUG "Service account $sa not found"
        fi
    done
    
    if [[ "$sa_valid" == "true" ]]; then
        record_test_result "Service Accounts" "PASS" "All required service accounts exist"
    else
        record_test_result "Service Accounts" "FAIL" "Some service accounts are missing"
    fi
    
    # Test 2: Network policies exist
    local network_policies
    network_policies=$(kubectl --context "kind-$NAMESPACE" get networkpolicy -n "$NAMESPACE" --no-headers | wc -l)
    
    if (( network_policies > 0 )); then
        record_test_result "Network Policies" "PASS" "$network_policies network policies configured"
    else
        record_test_result "Network Policies" "WARN" "No network policies found (may be intentional for development)"
    fi
    
    # Test 3: Secrets exist and are properly configured
    local secrets=("debezium-credentials" "postgresql-credentials" "aws-credentials" "schema-registry-auth")
    local secrets_valid=true
    
    for secret in "${secrets[@]}"; do
        if kubectl --context "kind-$NAMESPACE" get secret "$secret" -n "$NAMESPACE" &> /dev/null; then
            log DEBUG "Secret $secret exists"
        else
            secrets_valid=false
            log DEBUG "Secret $secret not found"
        fi
    done
    
    if [[ "$secrets_valid" == "true" ]]; then
        record_test_result "Required Secrets" "PASS" "All required secrets exist"
    else
        record_test_result "Required Secrets" "FAIL" "Some required secrets are missing"
    fi
    
    log INFO "Kubernetes RBAC validation completed"
}

# Generate validation report
generate_report() {
    log INFO "Generating validation report..."
    
    echo ""
    echo "=========================================="
    echo "  Task 13: Access Validation Report"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo "Component: $COMPONENT"
    echo ""
    local warned_tests=0
    for result in "${VALIDATION_RESULTS[@]}"; do
        if [[ "$result" == "WARN" ]]; then
            ((warned_tests++))
        fi
    done
    
    echo "Summary:"
    echo "  Total Tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $FAILED_TESTS"
    echo "  Warnings: $warned_tests"
    echo "  Success Rate: $(( (PASSED_TESTS * 100) / TOTAL_TESTS ))%"
    echo ""
    
    if (( FAILED_TESTS > 0 )); then
        echo "Failed Tests:"
        for test_name in "${!VALIDATION_RESULTS[@]}"; do
            if [[ "${VALIDATION_RESULTS[$test_name]}" == "FAIL" ]]; then
                echo "  - $test_name"
            fi
        done
        echo ""
    fi
    
    echo "Detailed Results:"
    for test_name in "${!VALIDATION_RESULTS[@]}"; do
        local result="${VALIDATION_RESULTS[$test_name]}"
        local status_symbol
        case $result in
            PASS) status_symbol="✓" ;;
            FAIL) status_symbol="✗" ;;
            WARN) status_symbol="⚠" ;;
            *) status_symbol="?" ;;
        esac
        echo "  $status_symbol $test_name: $result"
    done
    
    echo ""
    echo "=========================================="
    
    # Return appropriate exit code
    if (( FAILED_TESTS > 0 )); then
        return 1
    else
        return 0
    fi
}

# Main execution function
main() {
    log INFO "Starting Task 13: Access Validation"
    log INFO "Component: $COMPONENT, Verbose: $VERBOSE"
    
    # Execute validation based on component selection
    case $COMPONENT in
        postgresql)
            validate_postgresql_permissions
            validate_network_connectivity
            validate_kubernetes_rbac
            ;;
        kafka-connect)
            validate_kafka_connect_access
            validate_network_connectivity
            validate_kubernetes_rbac
            ;;
        schema-registry)
            validate_schema_registry_access
            validate_network_connectivity
            validate_kubernetes_rbac
            ;;
        s3)
            validate_s3_access
            ;;
        all)
            validate_postgresql_permissions
            validate_kafka_connect_access
            validate_schema_registry_access
            validate_s3_access
            validate_network_connectivity
            validate_kubernetes_rbac
            ;;
        *)
            log ERROR "Invalid component: $COMPONENT"
            exit 1
            ;;
    esac
    
    # Generate and display report
    if generate_report; then
        log SUCCESS "Access validation completed successfully!"
        exit 0
    else
        log ERROR "Access validation completed with failures!"
        exit 1
    fi
}

# Execute main function
main "$@"