#!/bin/bash
# daily-security-check.sh
# Automated daily security validation for data ingestion pipeline

set -e

NAMESPACE="data-ingestion"
LOG_DIR="/tmp/security-logs"
LOG_FILE="$LOG_DIR/security-check-$(date +%Y%m%d-%H%M%S).log"

# Create log directory
mkdir -p $LOG_DIR

echo "=== Daily Security Check - $(date) ===" | tee $LOG_FILE
echo "Namespace: $NAMESPACE" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Check for default/weak passwords
log_with_timestamp "=== Checking for Default/Weak Passwords ==="
log_with_timestamp "Analyzing secrets for weak passwords..."

# Get all secrets and check for common weak passwords
WEAK_PASSWORDS=("password" "changeme" "admin" "123456" "postgres" "kafka")
SECRET_FOUND=false

for secret in $(kubectl get secrets -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    log_with_timestamp "Checking secret: $secret"
    
    # Get secret data and decode
    SECRET_DATA=$(kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.data}' 2>/dev/null || echo "{}")
    
    if [ "$SECRET_DATA" != "{}" ]; then
        # Check each weak password
        for weak_pass in "${WEAK_PASSWORDS[@]}"; do
            ENCODED_WEAK=$(echo -n "$weak_pass" | base64 -w 0)
            if echo "$SECRET_DATA" | grep -q "$ENCODED_WEAK"; then
                log_with_timestamp "⚠️  WARNING: Weak password '$weak_pass' found in secret $secret"
                SECRET_FOUND=true
            fi
        done
    fi
done

if [ "$SECRET_FOUND" = false ]; then
    log_with_timestamp "✓ No weak passwords detected"
fi

echo "" | tee -a $LOG_FILE

# Check certificate expiration (if TLS enabled)
log_with_timestamp "=== Checking Certificate Expiration ==="
TLS_SECRETS=$(kubectl get secrets -n $NAMESPACE -o json | jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name' 2>/dev/null)

if [ -n "$TLS_SECRETS" ]; then
    for cert_secret in $TLS_SECRETS; do
        log_with_timestamp "Checking certificate in secret: $cert_secret"
        CERT_DATA=$(kubectl get secret $cert_secret -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d)
        EXPIRY=$(echo "$CERT_DATA" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
        log_with_timestamp "Certificate expires: $EXPIRY"
        
        # Check if certificate expires within 30 days
        EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
        CURRENT_EPOCH=$(date +%s)
        DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - CURRENT_EPOCH) / 86400 ))
        
        if [ $DAYS_UNTIL_EXPIRY -lt 30 ] && [ $DAYS_UNTIL_EXPIRY -gt 0 ]; then
            log_with_timestamp "⚠️  WARNING: Certificate expires in $DAYS_UNTIL_EXPIRY days"
        elif [ $DAYS_UNTIL_EXPIRY -le 0 ]; then
            log_with_timestamp "🚨 CRITICAL: Certificate has expired!"
        else
            log_with_timestamp "✓ Certificate valid for $DAYS_UNTIL_EXPIRY days"
        fi
    done
else
    log_with_timestamp "No TLS certificates found"
fi

echo "" | tee -a $LOG_FILE

# Check for pods running as root
log_with_timestamp "=== Checking for Pods Running as Root ==="
ROOT_PODS_FOUND=false

for pod in $(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    # Check security context
    RUN_AS_USER=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
    RUN_AS_NON_ROOT=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
    
    if [ "$RUN_AS_USER" = "0" ] || ([ -z "$RUN_AS_USER" ] && [ "$RUN_AS_NON_ROOT" != "true" ]); then
        log_with_timestamp "⚠️  WARNING: Pod $pod may be running as root"
        ROOT_PODS_FOUND=true
    else
        log_with_timestamp "✓ Pod $pod has proper security context (runAsUser: $RUN_AS_USER, runAsNonRoot: $RUN_AS_NON_ROOT)"
    fi
done

if [ "$ROOT_PODS_FOUND" = false ]; then
    log_with_timestamp "✓ No pods running as root detected"
fi

echo "" | tee -a $LOG_FILE

# Check service account token mounting
log_with_timestamp "=== Checking Service Account Token Mounting ==="
TOKEN_MOUNT_ISSUES=false

for sa in postgresql-sa kafka-sa debezium-sa schema-registry-sa kafka-connect-sa; do
    TOKEN_MOUNT=$(kubectl get serviceaccount $sa -n $NAMESPACE -o jsonpath='{.automountServiceAccountToken}' 2>/dev/null)
    if [ "$TOKEN_MOUNT" != "false" ]; then
        log_with_timestamp "⚠️  WARNING: Service account $sa has token mounting enabled or not set"
        TOKEN_MOUNT_ISSUES=true
    else
        log_with_timestamp "✓ Service account $sa has token mounting disabled"
    fi
done

if [ "$TOKEN_MOUNT_ISSUES" = false ]; then
    log_with_timestamp "✓ All service accounts have token mounting properly disabled"
fi

echo "" | tee -a $LOG_FILE

# Check network policies
log_with_timestamp "=== Checking Network Policies ==="
REQUIRED_POLICIES=("default-deny-all" "allow-dns" "postgresql-netpol" "kafka-netpol" "kafka-connect-netpol" "schema-registry-netpol")
MISSING_POLICIES=false

for policy in "${REQUIRED_POLICIES[@]}"; do
    if kubectl get networkpolicy $policy -n $NAMESPACE >/dev/null 2>&1; then
        log_with_timestamp "✓ Network policy $policy exists"
    else
        log_with_timestamp "⚠️  WARNING: Network policy $policy is missing"
        MISSING_POLICIES=true
    fi
done

if [ "$MISSING_POLICIES" = false ]; then
    log_with_timestamp "✓ All required network policies are present"
fi

echo "" | tee -a $LOG_FILE

# Check for security events in logs
log_with_timestamp "=== Checking for Security Events in Logs ==="
log_with_timestamp "Checking PostgreSQL logs for authentication failures..."
PG_AUTH_FAILURES=$(kubectl logs -n $NAMESPACE statefulset/postgresql --since=24h 2>/dev/null | grep -i "authentication\|failed\|error" | wc -l)
log_with_timestamp "PostgreSQL authentication events in last 24h: $PG_AUTH_FAILURES"

log_with_timestamp "Checking Schema Registry logs for authentication failures..."
SR_AUTH_FAILURES=$(kubectl logs -n $NAMESPACE deployment/schema-registry --since=24h 2>/dev/null | grep -E "401|403|authentication|unauthorized" | wc -l)
log_with_timestamp "Schema Registry auth events in last 24h: $SR_AUTH_FAILURES"

log_with_timestamp "Checking Kafka Connect logs for security events..."
KC_SECURITY_EVENTS=$(kubectl logs -n $NAMESPACE deployment/kafka-connect --since=24h 2>/dev/null | grep -i "access denied\|permission denied\|authentication\|unauthorized" | wc -l)
log_with_timestamp "Kafka Connect security events in last 24h: $KC_SECURITY_EVENTS"

echo "" | tee -a $LOG_FILE

# Check resource usage for anomalies
log_with_timestamp "=== Checking Resource Usage Anomalies ==="
log_with_timestamp "Current pod resource usage:"
kubectl top pods -n $NAMESPACE 2>/dev/null | tee -a $LOG_FILE || log_with_timestamp "Metrics server not available"

echo "" | tee -a $LOG_FILE

# Check for failed pods
log_with_timestamp "=== Checking Pod Health ==="
FAILED_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}')
if [ -n "$FAILED_PODS" ]; then
    log_with_timestamp "⚠️  WARNING: Failed pods detected: $FAILED_PODS"
else
    log_with_timestamp "✓ All pods are running successfully"
fi

echo "" | tee -a $LOG_FILE

# Generate summary
log_with_timestamp "=== Security Check Summary ==="
WARNINGS=$(grep -c "⚠️  WARNING" $LOG_FILE || echo "0")
CRITICALS=$(grep -c "🚨 CRITICAL" $LOG_FILE || echo "0")
SUCCESSES=$(grep -c "✓" $LOG_FILE || echo "0")

log_with_timestamp "Security check completed:"
log_with_timestamp "- Successful checks: $SUCCESSES"
log_with_timestamp "- Warnings: $WARNINGS"
log_with_timestamp "- Critical issues: $CRITICALS"

if [ $CRITICALS -gt 0 ]; then
    log_with_timestamp "🚨 CRITICAL ISSUES FOUND - IMMEDIATE ACTION REQUIRED"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    log_with_timestamp "⚠️  Warnings found - review recommended"
    exit 2
else
    log_with_timestamp "✅ All security checks passed"
    exit 0
fi