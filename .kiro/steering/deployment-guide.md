---
inclusion: manual
---

# Deployment Guide

## Pre-Deployment Checklist

### Environment Preparation
- [ ] **Infrastructure Ready**: Kubernetes cluster provisioned and accessible
- [ ] **Namespaces Created**: `data-pipeline`, `data-storage`, `data-pipeline-system`
- [ ] **Secrets Configured**: Database credentials, API keys, certificates
- [ ] **Storage Provisioned**: Persistent volumes for databases and logs
- [ ] **Network Policies**: Security policies and firewall rules applied

### Code Quality Gates
- [ ] **All Tests Pass**: Unit tests, integration tests, dbt tests
- [ ] **Code Review Complete**: All changes peer-reviewed and approved
- [ ] **Security Scan**: No critical vulnerabilities detected
- [ ] **Performance Validated**: Load testing completed successfully
- [ ] **Documentation Updated**: README, API docs, runbooks current

### Data Validation
- [ ] **Schema Compatibility**: Database migrations tested
- [ ] **Data Quality**: Source data validated and profiled
- [ ] **Backup Verified**: Current backups available and tested
- [ ] **Rollback Plan**: Data rollback procedures documented

## Deployment Process

### 1. Infrastructure Deployment
```bash
# Deploy infrastructure components first
cd terraform/
terraform plan -var-file="prod.tfvars"
terraform apply -var-file="prod.tfvars"

# Verify infrastructure
kubectl get nodes
kubectl get namespaces
```

### 2. Database Setup
```bash
# Deploy PostgreSQL
kubectl apply -f k8s/databases/postgres.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n data-storage

# Deploy ClickHouse
kubectl apply -f k8s/databases/clickhouse.yaml
kubectl wait --for=condition=ready pod -l app=clickhouse -n data-storage

# Initialize schemas
kubectl exec -it postgres-0 -n data-storage -- psql -U postgres -f /init/schema.sql
```

### 3. Application Deployment
```bash
# Build and push images
docker build -t your-registry/data-pipeline/airflow:v1.0.0 docker/airflow/
docker push your-registry/data-pipeline/airflow:v1.0.0

# Deploy Airflow
kubectl apply -f k8s/airflow/
kubectl wait --for=condition=ready pod -l app=airflow -n data-pipeline

# Deploy data generators
kubectl apply -f k8s/data-generator/
```

### 4. Configuration Validation
```bash
# Test database connections
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  airflow connections test postgres_default

# Validate dbt setup
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  dbt debug --project-dir /opt/airflow/dbt

# Test DAG parsing
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  airflow dags list
```

## Post-Deployment Verification

### System Health Checks
```bash
# Check all pods are running
kubectl get pods -A | grep -E "(data-pipeline|data-storage)"

# Verify services are accessible
kubectl get svc -n data-pipeline
kubectl get svc -n data-storage

# Check resource utilization
kubectl top pods -n data-pipeline
kubectl top nodes
```

### Functional Testing
```bash
# Trigger test DAG run
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  airflow dags trigger data_pipeline_main

# Monitor execution
kubectl logs -f deployment/airflow-scheduler -n data-pipeline

# Verify data flow
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT COUNT(*) FROM transactions;"
```

### Performance Validation
- [ ] **Pipeline Execution**: Complete end-to-end pipeline run
- [ ] **Response Times**: API endpoints respond within SLA
- [ ] **Resource Usage**: CPU/Memory within expected ranges
- [ ] **Data Throughput**: Processing rates meet requirements

## Monitoring Setup

### Observability Stack
```bash
# Deploy Prometheus
kubectl apply -f k8s/monitoring/prometheus.yaml

# Deploy Grafana
kubectl apply -f k8s/monitoring/grafana.yaml

# Configure dashboards
kubectl apply -f k8s/monitoring/dashboards/
```

### Alerting Configuration
```bash
# Configure alert rules
kubectl apply -f k8s/monitoring/alerts/

# Test alert delivery
kubectl exec -it prometheus-0 -n monitoring -- \
  promtool query instant 'up{job="airflow"}'
```

## Rollback Procedures

### Application Rollback
```bash
# Rollback Airflow deployment
kubectl rollout undo deployment/airflow-scheduler -n data-pipeline
kubectl rollout undo deployment/airflow-webserver -n data-pipeline

# Verify rollback
kubectl rollout status deployment/airflow-scheduler -n data-pipeline
```

### Database Rollback
```bash
# Restore from backup (if needed)
kubectl exec -it postgres-0 -n data-storage -- \
  pg_restore -U postgres -d transactions_db /backups/latest.dump

# Verify data integrity
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT COUNT(*) FROM users;"
```

## Environment-Specific Configurations

### Development Environment
```yaml
# dev-values.yaml
airflow:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
  debug: true
  
postgres:
  storage: 10Gi
  replicas: 1
```

### Production Environment
```yaml
# prod-values.yaml
airflow:
  replicas: 3
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 1000m
      memory: 4Gi
  
postgres:
  storage: 100Gi
  replicas: 2
  backup:
    enabled: true
    schedule: "0 2 * * *"
```

## Security Hardening

### Network Security
```bash
# Apply network policies
kubectl apply -f k8s/security/network-policies.yaml

# Verify policies
kubectl get networkpolicies -A
```

### RBAC Configuration
```bash
# Create service accounts
kubectl apply -f k8s/security/rbac.yaml

# Verify permissions
kubectl auth can-i create pods --as=system:serviceaccount:data-pipeline:airflow
```

### Secret Management
```bash
# Rotate secrets
kubectl create secret generic postgres-secret \
  --from-literal=username=postgres \
  --from-literal=password=$(openssl rand -base64 32) \
  -n data-storage

# Update deployments to use new secrets
kubectl rollout restart deployment/postgres -n data-storage
```

## Troubleshooting Guide

### Common Issues

#### Pod Startup Failures
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check logs
kubectl logs <pod-name> -n <namespace> --previous

# Check resource constraints
kubectl top pods -n <namespace>
```

#### Database Connection Issues
```bash
# Test connectivity
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  nc -zv postgres.data-storage.svc.cluster.local 5432

# Check DNS resolution
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  nslookup postgres.data-storage.svc.cluster.local
```

#### DAG Parsing Errors
```bash
# Check DAG syntax
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  python -m py_compile /opt/airflow/dags/data_pipeline_main.py

# Check imports
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  python -c "import sys; sys.path.append('/opt/airflow/dags'); import data_pipeline_main"
```

### Performance Issues

#### High Memory Usage
```bash
# Check memory usage
kubectl top pods -n data-pipeline

# Adjust resource limits
kubectl patch deployment airflow-scheduler -n data-pipeline -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"airflow-scheduler","resources":{"limits":{"memory":"4Gi"}}}]}}}}'
```

#### Slow Query Performance
```bash
# Check database performance
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE state = 'active';"

# Analyze slow queries
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT query, mean_time FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"
```

## Maintenance Procedures

### Regular Maintenance Tasks
- [ ] **Weekly**: Review system logs and performance metrics
- [ ] **Monthly**: Update dependencies and security patches
- [ ] **Quarterly**: Capacity planning and resource optimization
- [ ] **Annually**: Disaster recovery testing and documentation review

### Backup Procedures
```bash
# Database backup
kubectl exec -it postgres-0 -n data-storage -- \
  pg_dump -U postgres transactions_db > backup-$(date +%Y%m%d).sql

# Configuration backup
kubectl get configmaps -o yaml -n data-pipeline > configmaps-backup.yaml
kubectl get secrets -o yaml -n data-pipeline > secrets-backup.yaml
```

### Update Procedures
```bash
# Update application
kubectl set image deployment/airflow-scheduler \
  airflow-scheduler=your-registry/data-pipeline/airflow:v1.1.0 \
  -n data-pipeline

# Monitor rollout
kubectl rollout status deployment/airflow-scheduler -n data-pipeline

# Verify functionality
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  airflow dags trigger data_pipeline_main
```