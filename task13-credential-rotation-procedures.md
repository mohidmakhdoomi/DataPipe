# Credential Rotation Procedures

## Overview

This document provides step-by-step procedures for rotating credentials in the data ingestion pipeline. All procedures are designed for zero-downtime operation and include rollback steps for failure scenarios.

**Scope:** PostgreSQL CDC user, Schema Registry authentication, S3 access keys, and Kubernetes service account tokens.

## General Principles

### Rotation Strategy

1. **Dual-Credential Pattern:** Maintain both old and new credentials during transition
2. **Graceful Transition:** Allow services to reconnect with new credentials
3. **Validation:** Verify functionality before removing old credentials
4. **Rollback:** Maintain ability to revert if issues occur
5. **Audit Trail:** Log all rotation activities for compliance

### Rotation Schedule

| Credential Type | Development | Production | Emergency |
|----------------|-------------|------------|-----------|
| PostgreSQL CDC User | 90 days | 30 days | Immediate |
| Schema Registry Auth | 90 days | 60 days | Immediate |
| S3 Access Keys | 60 days | 30 days | Immediate |
| Service Account Tokens | 1 year (auto) | 1 year (auto) | Manual |

### Prerequisites

**Required Tools:**
- kubectl (configured for target cluster)
- psql (PostgreSQL client)
- aws CLI (configured with admin access)
- jq (JSON processor)
- openssl (for password generation)

**Required Access:**
- Kubernetes cluster admin
- PostgreSQL admin user
- AWS IAM admin
- Schema Registry admin

## PostgreSQL CDC User Rotation

### Procedure: Rotate PostgreSQL CDC User Password

**Duration:** ~10 minutes  
**Downtime:** None (zero-downtime)  
**Frequency:** 90 days (dev), 30 days (prod)

#### Step 1: Generate New Password

```bash
# Generate secure random password
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
echo "Generated new password: $NEW_PASSWORD"

# Store in temporary file for reference
echo "$NEW_PASSWORD" > /tmp/new_cdc_password.txt
chmod 600 /tmp/new_cdc_password.txt
```

#### Step 2: Update PostgreSQL User

```bash
# Connect to PostgreSQL and update password
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium PASSWORD '$NEW_PASSWORD';"

# Verify user can connect with new password
kubectl exec -n data-ingestion postgresql-0 -- psql -U debezium -d ecommerce -c \
  "SELECT current_user, current_database();" || {
  echo "ERROR: New password verification failed"
  exit 1
}

echo "✓ PostgreSQL user password updated successfully"
```

#### Step 3: Update Kubernetes Secret

```bash
# Create new secret with updated password
kubectl create secret generic postgresql-credentials-new \
  --namespace=data-ingestion \
  --from-literal=username=debezium \
  --from-literal=password="$NEW_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# Verify secret was created
kubectl get secret postgresql-credentials-new -n data-ingestion -o jsonpath='{.data.password}' | base64 -d
echo "✓ Kubernetes secret updated"
```

#### Step 4: Update Debezium Connector Configuration

```bash
# Get current connector configuration
kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors/postgres-cdc-connector/config > /tmp/current_config.json

# Update configuration with new secret reference
jq '.["database.password"] = "${env:DBZ_DB_PASSWORD_NEW}"' /tmp/current_config.json > /tmp/new_config.json

# Apply new configuration
kubectl exec -n data-ingestion kafka-connect-0 -- curl -X PUT \
  -H "Content-Type: application/json" \
  -d @/tmp/new_config.json \
  http://localhost:8083/connectors/postgres-cdc-connector/config

echo "✓ Debezium connector configuration updated"
```

#### Step 5: Update Deployment Environment Variables

```bash
# Update Kafka Connect deployment to use new secret
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

echo "✓ Deployment updated with new secret reference"
```

#### Step 6: Verify CDC Functionality

```bash
# Wait for pods to restart
kubectl rollout status deployment/kafka-connect -n data-ingestion --timeout=300s

# Check connector status
CONNECTOR_STATUS=$(kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors/postgres-cdc-connector/status | jq -r '.connector.state')

if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
  echo "✓ Debezium connector is running with new credentials"
else
  echo "✗ Connector status: $CONNECTOR_STATUS"
  echo "Check connector logs for issues"
  exit 1
fi

# Test CDC by inserting test record
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "INSERT INTO users (email, first_name, last_name) VALUES ('test@rotation.com', 'Test', 'Rotation');"

# Verify record appears in Kafka topic
sleep 10
kubectl exec -n data-ingestion kafka-0 -- kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic postgres.public.users \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 10000 | grep "test@rotation.com" && {
  echo "✓ CDC functionality verified"
} || {
  echo "✗ CDC verification failed"
  exit 1
}
```

#### Step 7: Cleanup Old Credentials

```bash
# Wait 24 hours before cleanup (grace period)
echo "Waiting 24 hours before cleaning up old credentials..."
echo "Run the following command after 24 hours:"
echo "kubectl delete secret postgresql-credentials -n data-ingestion"
echo "rm -f /tmp/new_cdc_password.txt"

# Schedule cleanup (optional)
cat > /tmp/cleanup_old_creds.sh << 'EOF'
#!/bin/bash
sleep 86400  # 24 hours
kubectl delete secret postgresql-credentials -n data-ingestion
rm -f /tmp/new_cdc_password.txt
echo "Old PostgreSQL credentials cleaned up"
EOF

chmod +x /tmp/cleanup_old_creds.sh
nohup /tmp/cleanup_old_creds.sh &
```

### Rollback Procedure

If issues occur during rotation:

```bash
# Revert to old secret
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
                "name": "postgresql-credentials",
                "key": "password"
              }
            }
          }]
        }]
      }
    }
  }
}'

# Wait for rollback
kubectl rollout status deployment/kafka-connect -n data-ingestion

# Verify connector is working
kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors/postgres-cdc-connector/status
```

## Schema Registry Authentication Rotation

### Procedure: Rotate Schema Registry Credentials

**Duration:** ~15 minutes  
**Downtime:** None (rolling restart)  
**Frequency:** 90 days (dev), 60 days (prod)

#### Step 1: Generate New Credentials

```bash
# Generate new username and password
NEW_SR_USER="schema-user-$(date +%Y%m%d)"
NEW_SR_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

echo "New Schema Registry user: $NEW_SR_USER"
echo "New Schema Registry password: $NEW_SR_PASSWORD"

# Store credentials temporarily
cat > /tmp/new_sr_credentials.txt << EOF
username=$NEW_SR_USER
password=$NEW_SR_PASSWORD
EOF
chmod 600 /tmp/new_sr_credentials.txt
```

#### Step 2: Update Schema Registry User Configuration

```bash
# Create new user properties file
kubectl create configmap schema-registry-users-new \
  --namespace=data-ingestion \
  --from-literal=user.properties="$NEW_SR_USER: $NEW_SR_PASSWORD,developer" \
  --dry-run=client -o yaml | kubectl apply -f -

# Update Schema Registry deployment to use new user file
kubectl patch deployment schema-registry -n data-ingestion --type='merge' -p='{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "schema-registry",
          "volumeMounts": [{
            "name": "users-config",
            "mountPath": "/etc/schema-registry/user.properties",
            "subPath": "user.properties"
          }]
        }],
        "volumes": [{
          "name": "users-config",
          "configMap": {
            "name": "schema-registry-users-new"
          }
        }]
      }
    }
  }
}'

# Wait for Schema Registry to restart
kubectl rollout status deployment/schema-registry -n data-ingestion --timeout=300s
echo "✓ Schema Registry updated with new user configuration"
```

#### Step 3: Test New Credentials

```bash
# Test authentication with new credentials
SR_ENDPOINT="http://schema-registry.data-ingestion.svc.cluster.local:8081"

kubectl run test-sr-auth --rm -i --tty --restart=Never --image=curlimages/curl -- \
  curl -u "$NEW_SR_USER:$NEW_SR_PASSWORD" \
  "$SR_ENDPOINT/subjects" && {
  echo "✓ New Schema Registry credentials verified"
} || {
  echo "✗ Schema Registry authentication failed"
  exit 1
}
```

#### Step 4: Update Kafka Connect Connector Configurations

```bash
# Update all connectors to use new Schema Registry credentials
CONNECTORS=$(kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors | jq -r '.[]')

for connector in $CONNECTORS; do
  echo "Updating connector: $connector"
  
  # Get current config
  kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
    "http://localhost:8083/connectors/$connector/config" > "/tmp/${connector}_config.json"
  
  # Update Schema Registry credentials
  jq --arg user "$NEW_SR_USER" --arg pass "$NEW_SR_PASSWORD" '
    .["key.converter.basic.auth.user.info"] = ($user + ":" + $pass) |
    .["value.converter.basic.auth.user.info"] = ($user + ":" + $pass)
  ' "/tmp/${connector}_config.json" > "/tmp/${connector}_config_new.json"
  
  # Apply updated config
  kubectl exec -n data-ingestion kafka-connect-0 -- curl -X PUT \
    -H "Content-Type: application/json" \
    -d @"/tmp/${connector}_config_new.json" \
    "http://localhost:8083/connectors/$connector/config"
  
  echo "✓ Updated connector: $connector"
done
```

#### Step 5: Verify All Connectors

```bash
# Check all connector statuses
echo "Verifying connector statuses..."

for connector in $CONNECTORS; do
  STATUS=$(kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
    "http://localhost:8083/connectors/$connector/status" | jq -r '.connector.state')
  
  if [ "$STATUS" = "RUNNING" ]; then
    echo "✓ $connector: RUNNING"
  else
    echo "✗ $connector: $STATUS"
  fi
done

# Test schema operations
kubectl exec -n data-ingestion kafka-connect-0 -- curl -u "$NEW_SR_USER:$NEW_SR_PASSWORD" \
  "$SR_ENDPOINT/subjects" | jq . && {
  echo "✓ Schema Registry operations verified"
} || {
  echo "✗ Schema Registry operations failed"
  exit 1
}
```

#### Step 6: Cleanup Old Credentials

```bash
# Schedule cleanup after 24-hour grace period
echo "Scheduling cleanup of old Schema Registry credentials..."

cat > /tmp/cleanup_sr_creds.sh << 'EOF'
#!/bin/bash
sleep 86400  # 24 hours
kubectl delete configmap schema-registry-users -n data-ingestion
rm -f /tmp/new_sr_credentials.txt /tmp/*_config*.json
echo "Old Schema Registry credentials cleaned up"
EOF

chmod +x /tmp/cleanup_sr_creds.sh
nohup /tmp/cleanup_sr_creds.sh &
```

## S3 Access Key Rotation

### Procedure: Rotate S3 Access Keys

**Duration:** ~5 minutes  
**Downtime:** None (dual-key transition)  
**Frequency:** 60 days (dev), 30 days (prod)

#### Step 1: Create New IAM Access Key

```bash
# Get current IAM user
IAM_USER=$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)
echo "Current IAM user: $IAM_USER"

# Create new access key
NEW_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER")
NEW_ACCESS_KEY=$(echo "$NEW_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_KEY=$(echo "$NEW_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')

echo "New access key created: $NEW_ACCESS_KEY"

# Store keys temporarily
cat > /tmp/new_aws_credentials.txt << EOF
aws_access_key_id=$NEW_ACCESS_KEY
aws_secret_access_key=$NEW_SECRET_KEY
EOF
chmod 600 /tmp/new_aws_credentials.txt
```

#### Step 2: Test New Access Key

```bash
# Test new credentials
export AWS_ACCESS_KEY_ID="$NEW_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$NEW_SECRET_KEY"

# Test S3 access
aws s3 ls s3://datapipe-ingestion-dev/ && {
  echo "✓ New S3 credentials verified"
} || {
  echo "✗ S3 access test failed"
  exit 1
}

# Reset environment
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
```

#### Step 3: Update Kubernetes Secret

```bash
# Create new secret with updated credentials
kubectl create secret generic aws-credentials-new \
  --namespace=data-ingestion \
  --from-literal=aws_access_key_id="$NEW_ACCESS_KEY" \
  --from-literal=aws_secret_access_key="$NEW_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Kubernetes secret updated with new S3 credentials"
```

#### Step 4: Update S3 Sink Connector

```bash
# Update S3 Sink connector configuration
kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors/s3-sink-connector/config > /tmp/s3_config.json

# Update with new credentials (using environment variable references)
jq '.["aws.access.key.id"] = "${env:AWS_ACCESS_KEY_ID}" |
    .["aws.secret.access.key"] = "${env:AWS_SECRET_ACCESS_KEY}"' \
    /tmp/s3_config.json > /tmp/s3_config_new.json

# Apply new configuration
kubectl exec -n data-ingestion kafka-connect-0 -- curl -X PUT \
  -H "Content-Type: application/json" \
  -d @/tmp/s3_config_new.json \
  http://localhost:8083/connectors/s3-sink-connector/config

echo "✓ S3 Sink connector configuration updated"
```

#### Step 5: Update Deployment Environment Variables

```bash
# Update Kafka Connect deployment to use new AWS credentials
kubectl patch deployment kafka-connect -n data-ingestion --type='merge' -p='{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "kafka-connect",
          "env": [
            {
              "name": "AWS_ACCESS_KEY_ID",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "aws-credentials-new",
                  "key": "aws_access_key_id"
                }
              }
            },
            {
              "name": "AWS_SECRET_ACCESS_KEY",
              "valueFrom": {
                "secretKeyRef": {
                  "name": "aws-credentials-new",
                  "key": "aws_secret_access_key"
                }
              }
            }
          ]
        }]
      }
    }
  }
}'

# Wait for deployment rollout
kubectl rollout status deployment/kafka-connect -n data-ingestion --timeout=300s
echo "✓ Kafka Connect deployment updated with new AWS credentials"
```

#### Step 6: Verify S3 Archival

```bash
# Check S3 Sink connector status
CONNECTOR_STATUS=$(kubectl exec -n data-ingestion kafka-connect-0 -- curl -s \
  http://localhost:8083/connectors/s3-sink-connector/status | jq -r '.connector.state')

if [ "$CONNECTOR_STATUS" = "RUNNING" ]; then
  echo "✓ S3 Sink connector is running with new credentials"
else
  echo "✗ S3 Sink connector status: $CONNECTOR_STATUS"
  exit 1
fi

# Test S3 archival by generating test data
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "INSERT INTO products (name, description, price) VALUES ('Test Product', 'Rotation Test', 99.99);"

# Wait for data to be archived
sleep 60

# Check if new data appears in S3
aws s3 ls s3://datapipe-ingestion-dev/topics/postgres.public.products/ --recursive | tail -5 && {
  echo "✓ S3 archival functionality verified"
} || {
  echo "✗ S3 archival verification failed"
}
```

#### Step 7: Deactivate Old Access Key

```bash
# Get old access key ID
OLD_ACCESS_KEY=$(kubectl get secret aws-credentials -n data-ingestion -o jsonpath='{.data.aws_access_key_id}' | base64 -d)

# Wait 24 hours before deactivating old key
echo "Scheduling deactivation of old access key: $OLD_ACCESS_KEY"

cat > /tmp/cleanup_aws_creds.sh << EOF
#!/bin/bash
sleep 86400  # 24 hours
aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$OLD_ACCESS_KEY"
kubectl delete secret aws-credentials -n data-ingestion
rm -f /tmp/new_aws_credentials.txt /tmp/s3_config*.json
echo "Old AWS credentials cleaned up"
EOF

chmod +x /tmp/cleanup_aws_creds.sh
nohup /tmp/cleanup_aws_creds.sh &
```

## Emergency Rotation Procedures

### Immediate Credential Revocation

When credentials are compromised:

#### Step 1: Immediate Revocation (< 5 minutes)

```bash
# PostgreSQL: Disable user immediately
kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d ecommerce -c \
  "ALTER USER debezium NOLOGIN;"

# S3: Deactivate access key immediately
aws iam update-access-key --user-name "$IAM_USER" --access-key-id "$COMPROMISED_KEY" --status Inactive

# Schema Registry: Remove user from configuration
kubectl delete configmap schema-registry-users -n data-ingestion
```

#### Step 2: Generate and Deploy New Credentials (< 30 minutes)

Follow the standard rotation procedures above, but skip grace periods and cleanup delays.

#### Step 3: Incident Documentation (< 1 hour)

```bash
# Create incident report
cat > "/tmp/security-incident-$(date +%Y%m%d-%H%M%S).md" << EOF
# Security Incident Report

**Date:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Type:** Credential Compromise
**Severity:** High
**Status:** Resolved

## Incident Details
- Compromised credential type: [SPECIFY]
- Detection method: [SPECIFY]
- Potential impact: [ASSESS]

## Response Actions
- Immediate revocation: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- New credentials deployed: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- Services restored: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Lessons Learned
- [DOCUMENT IMPROVEMENTS]
- [UPDATE PROCEDURES]
EOF
```

## Automation and Scheduling

### CronJob for Automated Rotation

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: credential-rotation
  namespace: data-ingestion
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: credential-rotation-sa
          containers:
          - name: rotation
            image: alpine:3.18
            command: ["/bin/sh"]
            args:
              - -c
              - |
                # Install required tools
                apk add --no-cache bash curl jq postgresql-client aws-cli
                
                # Run rotation checks
                /scripts/check-rotation-schedule.sh
                
                # Rotate credentials if needed
                if [ -f /tmp/rotation-needed ]; then
                  /scripts/rotate-credentials.sh
                fi
            volumeMounts:
            - name: rotation-scripts
              mountPath: /scripts
          volumes:
          - name: rotation-scripts
            configMap:
              name: credential-rotation-scripts
          restartPolicy: OnFailure
```

### Monitoring and Alerting

```bash
# Create monitoring script
cat > monitor-credential-age.sh << 'EOF'
#!/bin/bash
# Monitor credential age and alert when rotation is due

ALERT_DAYS=7  # Alert 7 days before rotation due

# Check PostgreSQL credential age
PG_SECRET_AGE=$(kubectl get secret postgresql-credentials -n data-ingestion -o jsonpath='{.metadata.creationTimestamp}')
PG_AGE_DAYS=$(( ($(date +%s) - $(date -d "$PG_SECRET_AGE" +%s)) / 86400 ))

if [ $PG_AGE_DAYS -gt $((90 - ALERT_DAYS)) ]; then
  echo "ALERT: PostgreSQL credentials due for rotation in $((90 - PG_AGE_DAYS)) days"
fi

# Similar checks for other credentials...
EOF
```

## Troubleshooting

### Common Issues

**Issue: Connector fails after rotation**
```bash
# Check connector logs
kubectl logs -n data-ingestion deployment/kafka-connect

# Verify credentials
kubectl exec -n data-ingestion kafka-connect-0 -- env | grep -E "(PASSWORD|KEY)"

# Test connectivity
kubectl exec -n data-ingestion kafka-connect-0 -- nc -zv postgresql 5432
```

**Issue: Schema Registry authentication fails**
```bash
# Test credentials manually
kubectl exec -n data-ingestion schema-registry-0 -- curl -u "user:pass" \
  http://localhost:8081/subjects

# Check user configuration
kubectl get configmap schema-registry-users -n data-ingestion -o yaml
```

**Issue: S3 access denied after rotation**
```bash
# Test AWS credentials
kubectl exec -n data-ingestion kafka-connect-0 -- aws s3 ls s3://bucket-name/

# Check IAM permissions
aws iam get-user-policy --user-name "$IAM_USER" --policy-name S3Access
```

## Document Control

**Version:** 1.0  
**Last Updated:** 2025-01-09  
**Next Review:** 2025-04-09  
**Owner:** Data Team  
**Approver:** Security Team  

**Related Documents:**
- task13-data-security-runbook.md
- task13-incident-response-playbook.md