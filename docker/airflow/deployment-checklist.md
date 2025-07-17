# Airflow Deployment Checklist

## Pre-Deployment

### ✅ Environment Setup
- [ ] Environment variables configured (`.env` file created from `.env.example`)
- [ ] Snowflake credentials available and tested
- [ ] AWS credentials configured (if using S3)
- [ ] Database connections verified
- [ ] ClickHouse service accessible

### ✅ Infrastructure
- [ ] Kubernetes cluster ready
- [ ] Namespaces created (`data-pipeline`, `data-storage`)
- [ ] Persistent volumes configured
- [ ] Network policies applied
- [ ] Resource quotas set

### ✅ Dependencies
- [ ] PostgreSQL database running with schema initialized
- [ ] ClickHouse service running with analytics database
- [ ] dbt project tested locally
- [ ] Docker images built and pushed to registry

## Deployment Steps

### 1. Build and Push Images
```bash
# Build Airflow image
cd docker/airflow
docker build -t your-registry/data-pipeline/airflow:latest .
docker push your-registry/data-pipeline/airflow:latest
```

### 2. Deploy Secrets
```bash
# Create secrets
kubectl apply -f ../k8s/secrets/
```

### 3. Deploy ConfigMaps
```bash
# Apply configuration
kubectl apply -f ../k8s/configmaps/
```

### 4. Deploy Airflow
```bash
# Deploy Airflow components
kubectl apply -f ../k8s/airflow/
```

### 5. Verify Deployment
```bash
# Check pod status
kubectl get pods -n data-pipeline

# Check services
kubectl get svc -n data-pipeline

# Check logs
kubectl logs -f deployment/airflow-scheduler -n data-pipeline
```

## Post-Deployment Verification

### ✅ Airflow Web UI
- [ ] Web UI accessible at configured URL
- [ ] Admin user can log in
- [ ] DAGs visible and not paused
- [ ] Connections configured correctly

### ✅ DAG Functionality
- [ ] `data_pipeline_main` DAG runs successfully
- [ ] `snowflake_pipeline` DAG connects to Snowflake
- [ ] `pipeline_monitoring` DAG reports healthy status
- [ ] Data quality checks pass

### ✅ Data Flow
- [ ] Data extracted from PostgreSQL
- [ ] dbt transformations complete successfully
- [ ] Data loaded to Snowflake (if configured)
- [ ] ClickHouse updated with real-time data
- [ ] Monitoring dashboard shows green status

### ✅ Monitoring & Alerting
- [ ] Pipeline monitoring DAG running every 15 minutes
- [ ] Data quality monitoring running every 6 hours
- [ ] SLA compliance tracking active
- [ ] Alert notifications configured (Slack/email)

## Configuration Validation

### Environment Variables
```bash
# Verify critical environment variables
echo $POSTGRES_HOST
echo $CLICKHOUSE_HOST
echo $SNOWFLAKE_ACCOUNT
echo $AIRFLOW_ENV
```

### Airflow Connections
```bash
# List configured connections
airflow connections list

# Test database connection
airflow connections test postgres_default

# Test Snowflake connection (if configured)
airflow connections test snowflake_default
```

### dbt Configuration
```bash
# Test dbt connection
dbt debug --target dev

# Test Snowflake target (if configured)
dbt debug --target snowflake
```

## Performance Tuning

### ✅ Resource Allocation
- [ ] CPU requests/limits set appropriately
- [ ] Memory requests/limits configured
- [ ] Storage volumes sized correctly
- [ ] Connection pool sizes optimized

### ✅ Scaling Configuration
- [ ] Horizontal Pod Autoscaler configured
- [ ] Worker concurrency settings tuned
- [ ] Database connection limits appropriate
- [ ] Queue sizes optimized

## Security Checklist

### ✅ Access Control
- [ ] RBAC policies applied
- [ ] Service accounts configured
- [ ] Network policies restricting traffic
- [ ] Pod security policies enforced

### ✅ Secrets Management
- [ ] No hardcoded credentials in code
- [ ] Kubernetes secrets encrypted at rest
- [ ] Secret rotation policy defined
- [ ] Audit logging enabled

## Backup & Recovery

### ✅ Data Backup
- [ ] Database backups scheduled
- [ ] Configuration backups automated
- [ ] DAG code versioned in Git
- [ ] Recovery procedures documented

### ✅ Disaster Recovery
- [ ] Multi-region deployment (if required)
- [ ] Backup restoration tested
- [ ] RTO/RPO requirements met
- [ ] Failover procedures documented

## Monitoring Setup

### ✅ Observability
- [ ] Prometheus metrics collection
- [ ] Grafana dashboards configured
- [ ] Log aggregation (ELK/Fluentd)
- [ ] Distributed tracing (if applicable)

### ✅ Alerting Rules
- [ ] Pipeline failure alerts
- [ ] Data freshness alerts
- [ ] Resource utilization alerts
- [ ] SLA breach notifications

## Maintenance

### ✅ Regular Tasks
- [ ] Log rotation configured
- [ ] Database maintenance scheduled
- [ ] Security updates planned
- [ ] Performance review scheduled

### ✅ Documentation
- [ ] Runbooks created
- [ ] Troubleshooting guides updated
- [ ] Architecture diagrams current
- [ ] Contact information updated

## Sign-off

- [ ] **Development Team**: Code review completed
- [ ] **DevOps Team**: Infrastructure validated
- [ ] **Data Team**: Data quality verified
- [ ] **Security Team**: Security review passed
- [ ] **Operations Team**: Monitoring configured

**Deployment Date**: ___________
**Deployed By**: ___________
**Approved By**: ___________

## Rollback Plan

In case of deployment issues:

1. **Immediate Rollback**:
   ```bash
   kubectl rollout undo deployment/airflow-scheduler -n data-pipeline
   kubectl rollout undo deployment/airflow-webserver -n data-pipeline
   ```

2. **Data Consistency Check**:
   - Verify no data corruption occurred
   - Check transaction logs
   - Validate data integrity

3. **Communication**:
   - Notify stakeholders
   - Document issues encountered
   - Plan remediation steps

## Post-Deployment Monitoring (First 24 Hours)

- [ ] **Hour 1**: Basic functionality verified
- [ ] **Hour 4**: First scheduled DAG runs completed
- [ ] **Hour 12**: Multiple DAG cycles successful
- [ ] **Hour 24**: Full monitoring cycle completed

**Notes**: ___________________________________________