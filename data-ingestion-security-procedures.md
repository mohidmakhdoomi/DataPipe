# Data Ingestion Pipeline - Security Procedures

## Overview

This document outlines the data-ingestion-specific security procedures for the PostgreSQL → Debezium CDC → Kafka → S3 archival pipeline. These procedures ensure secure credential management, proper data access controls, and compliance with security requirements.

## Credential Rotation Procedures

### PostgreSQL CDC User Credential Rotation

**Frequency**: Every 90 days or immediately upon suspected compromise

**Procedure**:

1. **Generate New Credentials**:
   ```bash
   # Generate new secure password
   NEW_PASSWORD=$(openssl rand -base64 32)
   echo "New password: $NEW_PASSWORD"
   ```

2. **Update PostgreSQL User**:
   ```sql
   -- Connect to PostgreSQL as superuser
   ALTER USER debezium WITH PASSWORD '$NEW_PASSWORD';
   
   -- Verify user permissions remain intact
   SELECT usename, userepl, usesuper FROM pg_user WHERE usename = 'debezium';
   ```

3. **Update Kubernetes Secret**:
   ```bash
   # Encode new password
   NEW_PASSWORD_B64=$(echo -n "$NEW_PASSWORD" | base64)
   
   # Update secret
   kubectl patch secret debezium-credentials -n data-ingestion \
     --type='json' \
     -p="[{'op': 'replace', 'path': '/data/db-password', 'value': '$NEW_PASSWORD_B64'}]"
   ```

4. **Restart Kafka Connect**:
   ```bash
   # Restart Kafka Connect to pick up new credentials
   kubectl rollout restart deployment kafka-connect -n data-ingestion
   
   # Wait for rollout to complete
   kubectl rollout status deployment kafka-connect -n data-ingestion
   ```

5. **Verify CDC Connector**:
   ```bash
   # Check connector status
   kubectl exec -n data-ingestion deployment/kafka-connect -- \
     curl -s http://localhost:8083/connectors/postgres-cdc-connector/status
   ```

### Schema Registry Credential Rotation

**Frequency**: Every 60 days or immediately upon suspected compromise

**Procedure**:

1. **Generate New Credentials**:
   ```bash
   # Generate new admin password
   ADMIN_PASSWORD=$(openssl rand -base64 24)
   # Generate new probe password  
   PROBE_PASSWORD=$(openssl rand -base64 24)
   ```

2. **Update Kubernetes Secret**:
   ```bash
   # Create new user-info content
   cat > /tmp/user-info <<EOF
   admin:$ADMIN_PASSWORD,admin
   probe:$PROBE_PASSWORD,readonly
   EOF
   
   # Update secret
   kubectl create secret generic schema-registry-auth \
     --from-file=user-info=/tmp/user-info \
     --from-literal=admin-user=admin \
     --from-literal=admin-password="$ADMIN_PASSWORD" \
     --from-literal=probe-user=probe \
     --from-literal=probe-password="$PROBE_PASSWORD" \
     --dry-run=client -o yaml | kubectl apply -f -
   
   # Clean up temp file
   rm /tmp/user-info
   ```

3. **Restart Schema Registry**:
   ```bash
   kubectl rollout restart deployment schema-registry -n data-ingestion
   kubectl rollout status deployment schema-registry -n data-ingestion
   ```

4. **Update Connector Configurations**:
   ```bash
   # Update Debezium connector with new credentials
   NEW_AUTH_B64=$(echo -n "admin:$ADMIN_PASSWORD" | base64)
   
   # Patch connector configuration (requires connector restart)
   kubectl exec -n data-ingestion deployment/kafka-connect -- \
     curl -X PUT http://localhost:8083/connectors/postgres-cdc-connector/config \
     -H "Content-Type: application/json" \
     -d '{
       "key.converter.basic.auth.user.info": "admin:'$ADMIN_PASSWORD'",
       "value.converter.basic.auth.user.info": "admin:'$ADMIN_PASSWORD'"
     }'
   ```

### AWS S3 Credential Rotation

**Frequency**: Every 90 days or immediately upon suspected compromise

**Procedure**:

1. **Create New AWS Access Keys** (via AWS Console or CLI):
   ```bash
   # Create new access key for IAM user
   aws iam create-access-key --user-name datapipe-s3-user
   ```

2. **Update Kubernetes Secret**:
   ```bash
   # Encode new credentials
   NEW_ACCESS_KEY_B64=$(echo -n "$NEW_ACCESS_KEY" | base64)
   NEW_SECRET_KEY_B64=$(echo -n "$NEW_SECRET_KEY" | base64)
   
   # Update secret
   kubectl patch secret aws-credentials -n data-ingestion \
     --type='json' \
     -p="[
       {'op': 'replace', 'path': '/data/access-key-id', 'value': '$NEW_ACCESS_KEY_B64'},
       {'op': 'replace', 'path': '/data/secret-access-key', 'value': '$NEW_SECRET_KEY_B64'}
     ]"
   ```

3. **Restart S3 Sink Connector**:
   ```bash
   # Restart connector to pick up new credentials
   kubectl exec -n data-ingestion deployment/kafka-connect -- \
     curl -X POST http://localhost:8083/connectors/s3-sink-connector/restart
   ```

4. **Deactivate Old AWS Access Keys**:
   ```bash
   # Wait 5 minutes for connector to stabilize, then deactivate old key
   sleep 300
   aws iam update-access-key --access-key-id $OLD_ACCESS_KEY --status Inactive --user-name datapipe-s3-user
   
   # After 24 hours, delete old key
   # aws iam delete-access-key --access-key-id $OLD_ACCESS_KEY --user-name datapipe-s3-user
   ```

## Data Access Control Validation

### PostgreSQL CDC User Permissions Audit

**Frequency**: Monthly

**Validation Script**:
```sql
-- Verify CDC user has minimal required permissions
SELECT 
    usename,
    userepl,
    usesuper,
    usecreatedb,
    usebypassrls
FROM pg_user 
WHERE usename = 'debezium';

-- Expected: userepl=true, all others=false

-- Verify table-level permissions
SELECT 
    schemaname,
    tablename,
    hasselect,
    hasinsert,
    hasupdate,
    hasdelete
FROM pg_tables t
LEFT JOIN (
    SELECT 
        schemaname,
        tablename,
        has_table_privilege('debezium', schemaname||'.'||tablename, 'SELECT') as hasselect,
        has_table_privilege('debezium', schemaname||'.'||tablename, 'INSERT') as hasinsert,
        has_table_privilege('debezium', schemaname||'.'||tablename, 'UPDATE') as hasupdate,
        has_table_privilege('debezium', schemaname||'.'||tablename, 'DELETE') as hasdelete
    FROM pg_tables
    WHERE schemaname = 'public'
) p USING (schemaname, tablename)
WHERE t.schemaname = 'public'
AND t.tablename IN ('users', 'products', 'orders', 'order_items');

-- Expected: hasselect=true, hasinsert/hasupdate/hasdelete=false

-- Verify replication slot ownership
SELECT slot_name, plugin, slot_type, active, active_pid 
FROM pg_replication_slots 
WHERE slot_name = 'debezium_slot';
```

### Kubernetes RBAC Validation

**Frequency**: Monthly

**Validation Script**:
```bash
#!/bin/bash
# validate-rbac.sh

echo "=== Validating Service Account Permissions ==="

# Check service account token mounting (should be disabled)
for sa in postgresql-sa kafka-sa debezium-sa schema-registry-sa kafka-connect-sa; do
    echo "Checking $sa token mounting..."
    kubectl get serviceaccount $sa -n data-ingestion -o jsonpath='{.automountServiceAccountToken}'
    echo ""
done

# Validate kafka-connect-sa permissions
echo "=== Validating kafka-connect-sa permissions ==="
kubectl auth can-i get configmaps --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n data-ingestion
kubectl auth can-i get secrets --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n data-ingestion
kubectl auth can-i get pods --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n data-ingestion

# Should NOT have these permissions
echo "=== Validating restricted permissions (should be 'no') ==="
kubectl auth can-i create pods --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n data-ingestion
kubectl auth can-i delete secrets --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n data-ingestion
kubectl auth can-i get secrets --as=system:serviceaccount:data-ingestion:kafka-connect-sa -n kube-system
```

### Network Policy Validation

**Frequency**: Monthly

**Validation Script**:
```bash
#!/bin/bash
# validate-network-policies.sh

echo "=== Network Policy Validation ==="

# Test PostgreSQL access restrictions
echo "Testing PostgreSQL network isolation..."
kubectl run test-pod --image=postgres:13 --rm -it --restart=Never -n data-ingestion -- \
  psql -h postgresql.data-ingestion.svc.cluster.local -U postgres -d ecommerce -c "SELECT 1;"

# Test Kafka access from unauthorized pods
echo "Testing Kafka network isolation..."
kubectl run unauthorized-pod --image=confluentinc/cp-kafka:7.4.0 --rm -it --restart=Never -n default -- \
  kafka-topics --bootstrap-server kafka-headless.data-ingestion.svc.cluster.local:9092 --list

# Test Schema Registry access
echo "Testing Schema Registry network isolation..."
kubectl run unauthorized-pod --image=curlimages/curl --rm -it --restart=Never -n default -- \
  curl -f http://schema-registry.data-ingestion.svc.cluster.local:8081/subjects

echo "Network policy validation complete."
```

## Security Monitoring and Alerting

### Security Event Monitoring

**Key Security Events to Monitor**:

1. **Failed Authentication Attempts**:
   ```bash
   # Monitor PostgreSQL logs for failed connections
   kubectl logs -n data-ingestion statefulset/postgresql | grep "FATAL.*authentication"
   
   # Monitor Schema Registry logs for auth failures
   kubectl logs -n data-ingestion deployment/schema-registry | grep "401\|403"
   ```

2. **Unusual Data Access Patterns**:
   ```bash
   # Monitor CDC connector for unusual table access
   kubectl logs -n data-ingestion deployment/kafka-connect | grep "Access denied\|Permission denied"
   ```

3. **Network Policy Violations**:
   ```bash
   # Check for dropped connections (requires CNI with logging)
   kubectl logs -n kube-system -l k8s-app=calico-node | grep "denied"
   ```

### Automated Security Checks

**Daily Security Validation Script**:
```bash
#!/bin/bash
# daily-security-check.sh

LOG_FILE="/tmp/security-check-$(date +%Y%m%d).log"

echo "=== Daily Security Check - $(date) ===" >> $LOG_FILE

# Check for default passwords
echo "Checking for default passwords..." >> $LOG_FILE
kubectl get secret -n data-ingestion -o jsonpath='{.items[*].data}' | \
  base64 -d | grep -i "changeme\|password\|admin" >> $LOG_FILE 2>&1

# Verify certificate expiration (if TLS enabled)
echo "Checking certificate expiration..." >> $LOG_FILE
kubectl get secrets -n data-ingestion -o json | \
  jq -r '.items[] | select(.type=="kubernetes.io/tls") | .metadata.name' | \
  while read cert; do
    kubectl get secret $cert -n data-ingestion -o jsonpath='{.data.tls\.crt}' | \
      base64 -d | openssl x509 -noout -dates >> $LOG_FILE 2>&1
  done

# Check for pods running as root
echo "Checking for pods running as root..." >> $LOG_FILE
kubectl get pods -n data-ingestion -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.runAsUser}{"\n"}{end}' >> $LOG_FILE

echo "Security check complete. Log: $LOG_FILE"
```

## Compliance and Audit Procedures

### Data Access Audit Trail

**Audit Log Collection**:
```bash
#!/bin/bash
# collect-audit-logs.sh

AUDIT_DIR="/tmp/audit-$(date +%Y%m%d)"
mkdir -p $AUDIT_DIR

# PostgreSQL access logs
kubectl logs -n data-ingestion statefulset/postgresql --since=24h > $AUDIT_DIR/postgresql-access.log

# Kafka Connect connector logs
kubectl logs -n data-ingestion deployment/kafka-connect --since=24h > $AUDIT_DIR/kafka-connect.log

# Schema Registry access logs
kubectl logs -n data-ingestion deployment/schema-registry --since=24h > $AUDIT_DIR/schema-registry.log

# Kubernetes API audit logs (if enabled)
kubectl get events -n data-ingestion --sort-by='.lastTimestamp' > $AUDIT_DIR/k8s-events.log

echo "Audit logs collected in: $AUDIT_DIR"
```

### Compliance Checklist

**Monthly Compliance Review**:

- [ ] All service accounts have `automountServiceAccountToken: false`
- [ ] CDC user has minimal required permissions (SELECT + REPLICATION only)
- [ ] Network policies enforce least-privilege access
- [ ] All secrets use strong, non-default passwords
- [ ] AWS S3 access uses least-privilege IAM policies
- [ ] No pods running as root or with unnecessary capabilities
- [ ] All inter-service communication uses service DNS names
- [ ] Dead letter queues are monitored for security events
- [ ] Credential rotation schedule is being followed
- [ ] Security monitoring alerts are functional

### Incident Response Procedures

**Security Incident Response**:

1. **Immediate Actions**:
   ```bash
   # Rotate all credentials immediately
   ./rotate-all-credentials.sh
   
   # Scale down affected components
   kubectl scale deployment kafka-connect --replicas=0 -n data-ingestion
   
   # Collect forensic logs
   ./collect-audit-logs.sh
   ```

2. **Investigation**:
   - Review audit logs for unauthorized access
   - Check network policy violations
   - Verify data integrity in S3 buckets
   - Analyze CDC event patterns for anomalies

3. **Recovery**:
   - Restore from known-good backups if needed
   - Update security configurations
   - Scale services back up
   - Monitor for continued suspicious activity

## Security Configuration Files

### Enhanced Network Policies

The current network policies provide comprehensive isolation. Key security features:

- **Default Deny All**: All traffic blocked by default
- **Least Privilege Access**: Only required ports and protocols allowed
- **External Access Control**: S3 access limited to HTTPS, IMDS blocked
- **DNS Resolution**: Controlled access to kube-dns only

### Pod Security Standards

All deployments should enforce these security contexts:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
  capabilities:
    drop:
    - ALL
```

### Secret Management Best Practices

- Use strong, randomly generated passwords
- Rotate credentials on schedule
- Never commit secrets to version control
- Use Kubernetes secrets with proper RBAC
- Consider external secret management (HashiCorp Vault, AWS Secrets Manager)

## Automation Scripts

All security procedures have been implemented as automated scripts in the `security-scripts/` directory:

### Master Script
```bash
# Run all security validations
./security-scripts/master-security-operations.sh validate-all

# Daily security check
./security-scripts/master-security-operations.sh daily-check

# Emergency lockdown
./security-scripts/master-security-operations.sh emergency-lockdown
```

### Individual Operations
```bash
# Credential rotation
./security-scripts/rotate-postgresql-credentials.sh
./security-scripts/rotate-schema-registry-credentials.sh

# Validation scripts
./security-scripts/validate-rbac.sh
./security-scripts/validate-network-policies.sh
./security-scripts/validate-cdc-permissions.sh
```

See `security-scripts/README.md` for complete documentation.

## Scheduled Automation

### Recommended Cron Schedule
```bash
# Daily security check at 2 AM
0 2 * * * /path/to/security-scripts/daily-security-check.sh

# Weekly RBAC validation on Sundays at 3 AM  
0 3 * * 0 /path/to/security-scripts/validate-rbac.sh

# Monthly CDC permissions audit on 1st of month at 4 AM
0 4 1 * * /path/to/security-scripts/validate-cdc-permissions.sh
```

## Conclusion

These security procedures ensure the data ingestion pipeline maintains strong security posture through:

- **Automated credential rotation** with 60-90 day cycles
- **Comprehensive access control validation** via RBAC and network policies
- **Continuous security monitoring** with daily automated checks
- **Compliance audit trails** with detailed logging and reporting
- **Emergency response capabilities** with immediate lockdown procedures

All procedures are fully automated and can be integrated into CI/CD pipelines for consistent execution. The security scripts provide comprehensive coverage of data-ingestion-specific security requirements while maintaining operational efficiency.