# Data Pipeline Security Incident Response Playbook

## Overview

This playbook provides step-by-step procedures for responding to security incidents affecting the data ingestion pipeline. It covers detection, containment, eradication, recovery, and lessons learned phases.

**Scope:** Security incidents affecting PostgreSQL CDC, Kafka streaming, Schema Registry, S3 archival, and Kubernetes infrastructure.

## Incident Classification

### Severity Levels

| Level | Description | Response Time | Escalation |
|-------|-------------|---------------|------------|
| **Critical** | Data breach, system compromise, service unavailable | < 15 minutes | Immediate |
| **High** | Credential compromise, unauthorized access, data corruption | < 1 hour | Within 2 hours |
| **Medium** | Policy violations, suspicious activity, performance impact | < 4 hours | Within 8 hours |
| **Low** | Configuration drift, minor policy violations | < 24 hours | Next business day |

### Incident Types

**Data Security Incidents:**
- Unauthorized data access
- Data exfiltration
- Data corruption or loss
- Credential compromise
- Privilege escalation

**Infrastructure Security Incidents:**
- System compromise
- Malware detection
- Network intrusion
- Service disruption
- Configuration tampering

**Compliance Incidents:**
- Policy violations
- Audit findings
- Regulatory breaches
- Access control failures
- Logging failures

## Incident Response Team

### Roles and Responsibilities

**Incident Commander (IC):**
- Overall incident coordination
- Communication with stakeholders
- Decision making authority
- Resource allocation

**Technical Lead:**
- Technical investigation
- System analysis and forensics
- Recovery planning and execution
- Root cause analysis

**Security Analyst:**
- Security assessment
- Threat analysis
- Evidence collection
- Security tool coordination

**Communications Lead:**
- Stakeholder notifications
- Status updates
- Documentation
- External communications

### Contact Information

**Primary Team:**
- Incident Commander: [Data Team Lead]
- Technical Lead: [Senior Data Engineer]
- Security Analyst: [Security Team Member]
- Communications Lead: [DevOps Team Lead]

**Escalation Contacts:**
- Security Team Manager
- Engineering Director
- Legal Counsel (for data breaches)
- Compliance Officer

## Detection and Alerting

### Automated Detection

**Security Monitoring Alerts:**
```bash
# Failed authentication attempts
kubectl logs -n data-ingestion --selector=app=postgresql | grep "authentication failed"

# Unauthorized API access
kubectl logs -n data-ingestion --selector=app=kafka-connect | grep "403\|401"

# Network policy violations
kubectl get events -n data-ingestion --field-selector reason=NetworkPolicyViolation

# RBAC violations
kubectl get events --field-selector reason=Forbidden
```

**Performance Anomalies:**
- Unusual data volume patterns
- Unexpected network traffic
- Resource consumption spikes
- Service response time degradation

### Manual Detection

**Regular Security Checks:**
```bash
# Run security audit
kubectl apply -f task13-security-audit-job.yaml
kubectl logs -n data-ingestion job/data-pipeline-security-audit

# Check for suspicious activities
./task13-validate-cdc-permissions.sh
./task13-audit-s3-policies.sh
./task13-network-policy-validation.sh
./task13-rbac-audit.sh
```

## Incident Response Procedures

### Phase 1: Detection and Analysis (0-15 minutes)

#### Step 1: Initial Assessment

```bash
# Document incident start time
INCIDENT_START=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
INCIDENT_ID="INC-$(date +%Y%m%d-%H%M%S)"

echo "Incident ID: $INCIDENT_ID"
echo "Start Time: $INCIDENT_START"

# Create incident directory
mkdir -p "/tmp/incidents/$INCIDENT_ID"
cd "/tmp/incidents/$INCIDENT_ID"
```

#### Step 2: Gather Initial Information

```bash
# Collect system status
kubectl get pods -n data-ingestion -o wide > pods-status.txt
kubectl get events -n data-ingestion --sort-by='.lastTimestamp' > events.txt
kubectl top pods -n data-ingestion > resource-usage.txt

# Collect recent logs
kubectl logs -n data-ingestion --selector=app=postgresql --since=1h > postgresql-logs.txt
kubectl logs -n data-ingestion --selector=app=kafka --since=1h > kafka-logs.txt
kubectl logs -n data-ingestion --selector=app=kafka-connect --since=1h > kafka-connect-logs.txt
kubectl logs -n data-ingestion --selector=app=schema-registry --since=1h > schema-registry-logs.txt

# Check network connectivity
./task13-network-policy-validation.sh > network-status.txt
```

#### Step 3: Classify Incident

```bash
# Determine incident type and severity
cat > incident-classification.txt << EOF
Incident ID: $INCIDENT_ID
Type: [DATA_BREACH|CREDENTIAL_COMPROMISE|SYSTEM_COMPROMISE|POLICY_VIOLATION]
Severity: [CRITICAL|HIGH|MEDIUM|LOW]
Affected Systems: [LIST_SYSTEMS]
Potential Impact: [DESCRIBE_IMPACT]
Initial Assessment: [BRIEF_DESCRIPTION]
EOF
```

### Phase 2: Containment (15 minutes - 1 hour)

#### Immediate Containment Actions

**For Credential Compromise:**
```bash
# Disable compromised PostgreSQL user
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium NOLOGIN;"

# Deactivate compromised S3 access key
aws iam update-access-key --user-name "$IAM_USER" --access-key-id "$COMPROMISED_KEY" --status Inactive

# Remove compromised Schema Registry user
kubectl patch configmap schema-registry-users -n data-ingestion --type='json' \
  -p='[{"op": "remove", "path": "/data/user.properties"}]'
```

**For System Compromise:**
```bash
# Isolate affected pods
kubectl label pods -n data-ingestion -l app=AFFECTED_APP quarantine=true

# Apply emergency network policy (deny all)
cat > emergency-network-policy.yaml << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: emergency-isolation
  namespace: data-ingestion
spec:
  podSelector:
    matchLabels:
      quarantine: "true"
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
EOF

kubectl apply -f emergency-network-policy.yaml
```

**For Data Breach:**
```bash
# Stop data processing immediately
kubectl scale deployment kafka-connect --replicas=0 -n data-ingestion

# Preserve evidence
kubectl get pods -n data-ingestion -o yaml > pods-snapshot.yaml
kubectl get secrets -n data-ingestion -o yaml > secrets-snapshot.yaml
kubectl get configmaps -n data-ingestion -o yaml > configmaps-snapshot.yaml

# Notify legal and compliance teams
echo "CRITICAL: Data breach detected in data pipeline" | \
  mail -s "URGENT: Data Breach - $INCIDENT_ID" legal@company.com compliance@company.com
```

#### Short-term Containment

```bash
# Implement additional monitoring
kubectl apply -f enhanced-monitoring.yaml

# Enable detailed logging
kubectl patch deployment kafka-connect -n data-ingestion --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "LOG_LEVEL", "value": "DEBUG"}}]'

# Create forensic snapshots
kubectl exec -n data-ingestion postgresql-0 -- pg_dump -U postgres ecommerce > database-snapshot.sql
```

### Phase 3: Eradication (1-4 hours)

#### Root Cause Analysis

```bash
# Analyze logs for attack vectors
grep -i "error\|fail\|unauthorized\|denied" *-logs.txt > security-events.txt

# Check for indicators of compromise
grep -E "(malware|virus|trojan|backdoor)" *-logs.txt > malware-indicators.txt

# Analyze network traffic patterns
kubectl exec -n data-ingestion kafka-connect-0 -- netstat -an > network-connections.txt

# Review recent configuration changes
kubectl get events -n data-ingestion --field-selector reason=ConfigMapUpdated,reason=SecretUpdated > config-changes.txt
```

#### Remove Threats

```bash
# Update all credentials (emergency rotation)
./emergency-credential-rotation.sh

# Apply security patches
kubectl set image deployment/kafka-connect kafka-connect=confluentinc/cp-kafka-connect:latest -n data-ingestion
kubectl set image deployment/schema-registry schema-registry=confluentinc/cp-schema-registry:latest -n data-ingestion

# Remove malicious configurations
kubectl delete configmap suspicious-config -n data-ingestion
kubectl delete secret compromised-secret -n data-ingestion

# Update network policies
kubectl apply -f hardened-network-policies.yaml
```

#### Vulnerability Assessment

```bash
# Scan for vulnerabilities
kubectl run security-scan --rm -i --tty --restart=Never --image=aquasec/trivy -- \
  image confluentinc/cp-kafka-connect:latest

# Check for misconfigurations
./task13-rbac-audit.sh > rbac-assessment.txt
./task13-network-policy-validation.sh > network-assessment.txt

# Validate security controls
./task13-validate-cdc-permissions.sh > permissions-assessment.txt
./task13-audit-s3-policies.sh > s3-assessment.txt
```

### Phase 4: Recovery (4-8 hours)

#### Service Restoration

```bash
# Restore services with new credentials
kubectl apply -f updated-postgresql-secret.yaml
kubectl apply -f updated-s3-credentials.yaml
kubectl apply -f updated-schema-registry-config.yaml

# Restart services in order
kubectl rollout restart deployment/schema-registry -n data-ingestion
kubectl rollout status deployment/schema-registry -n data-ingestion

kubectl rollout restart deployment/kafka-connect -n data-ingestion
kubectl rollout status deployment/kafka-connect -n data-ingestion

# Verify service functionality
./verify-pipeline-health.sh
```

#### Data Integrity Verification

```bash
# Check data consistency
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "SELECT COUNT(*) FROM users; SELECT COUNT(*) FROM products; SELECT COUNT(*) FROM orders;"

# Verify CDC functionality
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "INSERT INTO users (email, first_name, last_name) VALUES ('recovery-test@company.com', 'Recovery', 'Test');"

# Check Kafka topics
kubectl exec -n data-ingestion kafka-0 -- kafka-topics.sh --bootstrap-server localhost:9092 --list

# Verify S3 archival
aws s3 ls s3://datapipe-ingestion-dev/topics/ --recursive | tail -10
```

#### Monitoring Enhancement

```bash
# Deploy enhanced monitoring
kubectl apply -f enhanced-security-monitoring.yaml

# Configure additional alerts
kubectl apply -f security-alerts.yaml

# Enable audit logging
kubectl patch deployment kafka-connect -n data-ingestion --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "AUDIT_LOGGING", "value": "true"}}]'
```

### Phase 5: Lessons Learned (Within 1 week)

#### Post-Incident Review

```bash
# Create incident report
cat > incident-report-$INCIDENT_ID.md << EOF
# Security Incident Report

**Incident ID:** $INCIDENT_ID
**Date:** $INCIDENT_START
**Duration:** [CALCULATE_DURATION]
**Severity:** [FINAL_SEVERITY]
**Status:** Resolved

## Executive Summary
[BRIEF_OVERVIEW]

## Timeline
- Detection: $INCIDENT_START
- Containment: [TIME]
- Eradication: [TIME]
- Recovery: [TIME]
- Closure: [TIME]

## Root Cause
[DETAILED_ROOT_CAUSE_ANALYSIS]

## Impact Assessment
- Systems affected: [LIST]
- Data affected: [ASSESSMENT]
- Service downtime: [DURATION]
- Business impact: [DESCRIPTION]

## Response Actions
[DETAILED_ACTIONS_TAKEN]

## Lessons Learned
[KEY_LEARNINGS]

## Recommendations
[IMPROVEMENT_RECOMMENDATIONS]

## Action Items
- [ ] Update security procedures
- [ ] Implement additional controls
- [ ] Conduct security training
- [ ] Review and test incident response
EOF
```

#### Process Improvements

```bash
# Update security procedures
cp task13-data-security-runbook.md task13-data-security-runbook-v1.1.md
# [MAKE_IMPROVEMENTS_BASED_ON_LESSONS_LEARNED]

# Update monitoring and alerting
kubectl apply -f improved-monitoring.yaml

# Schedule security training
echo "Schedule security training for team based on incident learnings"

# Test incident response procedures
echo "Schedule tabletop exercise to test updated procedures"
```

## Specific Incident Scenarios

### Scenario 1: PostgreSQL Credential Compromise

**Detection:**
- Multiple failed authentication attempts
- Unusual database queries
- Data access from unexpected sources

**Response:**
```bash
# Immediate containment
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium NOLOGIN;"

# Generate new credentials
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Update PostgreSQL
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium PASSWORD '$NEW_PASSWORD';"

# Update Kubernetes secret
kubectl create secret generic postgresql-credentials-new \
  --namespace=data-ingestion \
  --from-literal=username=debezium \
  --from-literal=password="$NEW_PASSWORD"

# Update deployment
kubectl patch deployment kafka-connect -n data-ingestion --type='merge' -p='{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "kafka-connect",
          "env": [{
            "name": "DBZ_DB_PASSWORD",
            "valueFrom": {
              "secretKeyRef": {
                "name": "postgresql-credentials-new",
                "key": "password"
              }
            }
          }]
        }]
      }
    }
  }
}'

# Re-enable user
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium LOGIN;"
```

### Scenario 2: S3 Data Exfiltration

**Detection:**
- Unusual S3 access patterns
- Large data downloads
- Access from unexpected IP addresses

**Response:**
```bash
# Immediate containment
aws iam update-access-key --user-name "$IAM_USER" --access-key-id "$COMPROMISED_KEY" --status Inactive

# Stop S3 archival
kubectl scale deployment kafka-connect --replicas=0 -n data-ingestion

# Analyze S3 access logs
aws s3 cp s3://access-logs-bucket/logs/ . --recursive
grep "COMPROMISED_KEY" *.log > suspicious-access.txt

# Create new access key
NEW_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER")
NEW_ACCESS_KEY=$(echo "$NEW_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_KEY=$(echo "$NEW_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')

# Update Kubernetes secret
kubectl create secret generic aws-credentials-new \
  --namespace=data-ingestion \
  --from-literal=aws_access_key_id="$NEW_ACCESS_KEY" \
  --from-literal=aws_secret_access_key="$NEW_SECRET_KEY"

# Restore service with new credentials
kubectl scale deployment kafka-connect --replicas=1 -n data-ingestion
```

### Scenario 3: Kubernetes RBAC Privilege Escalation

**Detection:**
- Unauthorized API access
- Service account permission changes
- Suspicious pod creation

**Response:**
```bash
# Identify compromised service account
COMPROMISED_SA=$(kubectl get events --field-selector reason=Forbidden -o json | \
  jq -r '.items[0].involvedObject.name')

# Disable service account
kubectl patch serviceaccount "$COMPROMISED_SA" -n data-ingestion --type='merge' -p='{
  "automountServiceAccountToken": false
}'

# Remove role bindings
kubectl delete rolebinding "$COMPROMISED_SA-binding" -n data-ingestion
kubectl delete clusterrolebinding "$COMPROMISED_SA-cluster-binding"

# Create new service account
kubectl create serviceaccount "$COMPROMISED_SA-new" -n data-ingestion

# Apply minimal permissions
kubectl apply -f minimal-rbac-policy.yaml

# Update deployments
kubectl patch deployment kafka-connect -n data-ingestion --type='merge' -p='{
  "spec": {
    "template": {
      "spec": {
        "serviceAccountName": "'$COMPROMISED_SA'-new"
      }
    }
  }
}'
```

## Communication Templates

### Initial Notification

```
Subject: SECURITY INCIDENT - Data Pipeline - $INCIDENT_ID

INCIDENT ALERT
Incident ID: $INCIDENT_ID
Severity: [SEVERITY]
Status: Under Investigation
Affected Systems: Data Ingestion Pipeline

Initial Assessment:
[BRIEF_DESCRIPTION]

Actions Taken:
- Incident response team activated
- Initial containment measures implemented
- Investigation in progress

Next Update: [TIME]

Incident Commander: [NAME]
Contact: [EMAIL/PHONE]
```

### Status Update

```
Subject: UPDATE - Security Incident $INCIDENT_ID

INCIDENT UPDATE
Incident ID: $INCIDENT_ID
Status: [CONTAINED|INVESTIGATING|RECOVERING]
Time Since Detection: [DURATION]

Current Situation:
[DETAILED_UPDATE]

Actions Completed:
- [LIST_ACTIONS]

Next Steps:
- [LIST_NEXT_STEPS]

Estimated Resolution: [TIME]
Next Update: [TIME]
```

### Resolution Notification

```
Subject: RESOLVED - Security Incident $INCIDENT_ID

INCIDENT RESOLVED
Incident ID: $INCIDENT_ID
Resolution Time: [DURATION]
Final Impact: [ASSESSMENT]

Summary:
[INCIDENT_SUMMARY]

Resolution Actions:
- [LIST_RESOLUTION_ACTIONS]

Preventive Measures:
- [LIST_IMPROVEMENTS]

Post-Incident Review: [SCHEDULED_DATE]

Thank you for your patience during this incident.
```

## Testing and Validation

### Tabletop Exercises

**Monthly Scenario Testing:**
1. Credential compromise simulation
2. Data breach response drill
3. System compromise scenario
4. Network intrusion exercise

**Exercise Format:**
- 2-hour facilitated session
- All team members participate
- Document lessons learned
- Update procedures based on findings

### Incident Response Metrics

**Key Performance Indicators:**
- Mean Time to Detection (MTTD)
- Mean Time to Containment (MTTC)
- Mean Time to Recovery (MTTR)
- Incident recurrence rate
- False positive rate

**Target Metrics:**
- MTTD: < 15 minutes
- MTTC: < 1 hour
- MTTR: < 4 hours
- Recurrence: < 5%
- False positives: < 10%

## Document Control

**Version:** 1.0  
**Last Updated:** 2025-01-09  
**Next Review:** 2025-04-09  
**Owner:** Security Team  
**Approver:** CISO  

**Change History:**
- v1.0 (2025-01-09): Initial version for Task 13 implementation

**Related Documents:**
- task13-data-security-runbook.md
- task13-credential-rotation-procedures.md
- Emergency Contact List
- Legal and Compliance Procedures