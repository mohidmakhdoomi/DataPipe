# Data Ingestion Pipeline Security Scripts

This directory contains security automation scripts for the PostgreSQL → Debezium CDC → Kafka → S3 data ingestion pipeline.

## Overview

The security scripts implement comprehensive security procedures including:
- Credential rotation automation
- RBAC validation
- Network policy validation
- CDC user permission auditing
- Daily security monitoring
- Emergency response procedures

## Scripts

### Master Script
- **`master-security-operations.sh`** - Main orchestration script for all security operations

### Credential Rotation
- **`rotate-postgresql-credentials.sh`** - Rotates PostgreSQL CDC user credentials
- **`rotate-schema-registry-credentials.sh`** - Rotates Schema Registry authentication credentials

### Validation Scripts
- **`validate-rbac.sh`** - Validates Kubernetes RBAC configuration
- **`validate-network-policies.sh`** - Tests network policy enforcement
- **`validate-cdc-permissions.sh`** - Audits PostgreSQL CDC user permissions

### Monitoring
- **`daily-security-check.sh`** - Automated daily security validation

## Quick Start

### Run Complete Security Validation
```bash
./security-scripts/master-security-operations.sh validate-all
```

### Daily Security Check
```bash
./security-scripts/master-security-operations.sh daily-check
```

### Rotate Credentials
```bash
# PostgreSQL CDC user
./security-scripts/master-security-operations.sh rotate-postgresql

# Schema Registry
./security-scripts/master-security-operations.sh rotate-schema-registry
```

### Emergency Procedures
```bash
# Emergency lockdown (scales down services, rotates credentials)
./security-scripts/master-security-operations.sh emergency-lockdown
```

## Individual Script Usage

### PostgreSQL Credential Rotation
```bash
./security-scripts/rotate-postgresql-credentials.sh
```
- Generates new secure password
- Updates PostgreSQL user
- Updates Kubernetes secret
- Restarts Kafka Connect
- Verifies CDC connector status

### Schema Registry Credential Rotation
```bash
./security-scripts/rotate-schema-registry-credentials.sh
```
- Generates new admin and probe passwords
- Updates Kubernetes secret
- Restarts Schema Registry
- Updates connector configurations
- Verifies new credentials

### RBAC Validation
```bash
./security-scripts/validate-rbac.sh
```
- Checks service account token mounting
- Validates kafka-connect-sa permissions
- Ensures other service accounts have minimal permissions
- Verifies Role and RoleBinding configuration

### Network Policy Validation
```bash
./security-scripts/validate-network-policies.sh
```
- Tests authorized access patterns
- Verifies unauthorized access is blocked
- Validates cross-namespace isolation
- Checks external connectivity rules

### CDC Permissions Audit
```bash
./security-scripts/validate-cdc-permissions.sh
```
- Validates CDC user attributes
- Checks table-level permissions
- Verifies replication slot status
- Audits publication configuration
- Validates WAL settings

### Daily Security Check
```bash
./security-scripts/daily-security-check.sh
```
- Scans for weak passwords
- Checks certificate expiration
- Identifies pods running as root
- Validates service account configuration
- Monitors security events in logs

## Automation and Scheduling

### Cron Job Setup
Add to crontab for automated security monitoring:

```bash
# Daily security check at 2 AM
0 2 * * * /path/to/security-scripts/daily-security-check.sh

# Weekly RBAC validation on Sundays at 3 AM
0 3 * * 0 /path/to/security-scripts/validate-rbac.sh

# Monthly CDC permissions audit on 1st of month at 4 AM
0 4 1 * * /path/to/security-scripts/validate-cdc-permissions.sh
```

### Credential Rotation Schedule
- **PostgreSQL CDC User**: Every 90 days
- **Schema Registry**: Every 60 days
- **AWS S3 Credentials**: Every 90 days (manual via AWS Console)

## Security Monitoring

### Log Locations
- Daily security check logs: `/tmp/security-logs/`
- Emergency lockdown logs: `/tmp/emergency-logs-YYYYMMDD-HHMMSS/`

### Key Metrics to Monitor
- Failed authentication attempts
- Network policy violations
- Unusual data access patterns
- Certificate expiration warnings
- Resource usage anomalies

## Incident Response

### Security Incident Procedure
1. **Immediate Response**:
   ```bash
   ./security-scripts/master-security-operations.sh emergency-lockdown
   ```

2. **Investigation**:
   - Review collected forensic logs
   - Analyze security events
   - Check data integrity

3. **Recovery**:
   - Update security configurations
   - Scale services back up
   - Monitor for continued issues

### Emergency Contacts
- Security Team: [security@company.com]
- Infrastructure Team: [infra@company.com]
- On-call Engineer: [oncall@company.com]

## Prerequisites

### Required Tools
- `kubectl` - Kubernetes CLI
- `jq` - JSON processor
- `base64` - Base64 encoding/decoding
- `openssl` - Cryptographic operations
- `curl` - HTTP client

### Required Permissions
- Kubernetes cluster access
- Read/write access to `data-ingestion` namespace
- PostgreSQL superuser access (for credential rotation)

## Troubleshooting

### Common Issues

#### Script Permission Denied
```bash
chmod +x security-scripts/*.sh
```

#### Kubectl Not Found
```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

#### PostgreSQL Connection Failed
- Verify PostgreSQL pod is running
- Check network policies allow access
- Validate credentials in secrets

#### Kafka Connect Restart Failed
- Check resource constraints
- Verify connector configurations
- Review Kafka Connect logs

## Security Best Practices

### Credential Management
- Use strong, randomly generated passwords
- Rotate credentials on schedule
- Never commit secrets to version control
- Use Kubernetes secrets with proper RBAC

### Network Security
- Maintain default-deny network policies
- Regularly test network isolation
- Monitor for policy violations
- Limit external connectivity to HTTPS only

### Access Control
- Follow principle of least privilege
- Disable service account token mounting
- Regular RBAC audits
- Monitor for privilege escalation

### Monitoring
- Implement continuous security monitoring
- Set up alerting for security events
- Regular security assessments
- Maintain audit trails

## Contributing

When adding new security procedures:
1. Follow existing script patterns
2. Include comprehensive error handling
3. Add validation and verification steps
4. Update this README
5. Test thoroughly in development environment

## Support

For issues with security scripts:
1. Check script logs for error details
2. Verify prerequisites are met
3. Test individual components
4. Contact security team if needed