---
inclusion: manual
---

# Troubleshooting Guide

## Common Issues and Solutions

### Airflow DAG Issues

#### DAG Not Appearing in UI
**Symptoms**: DAG doesn't show up in Airflow web interface
**Causes & Solutions**:
```bash
# Check DAG syntax
python -m py_compile /opt/airflow/dags/your_dag.py

# Check DAG parsing errors
airflow dags list-import-errors

# Verify DAG bag loading
airflow dags list | grep your_dag_id

# Check scheduler logs
kubectl logs deployment/airflow-scheduler -n data-pipeline
```

#### Task Failures
**Symptoms**: Tasks fail with various error messages
**Common Solutions**:
```python
# Check task logs
airflow tasks log <dag_id> <task_id> <execution_date>

# Test task locally
airflow tasks test <dag_id> <task_id> <execution_date>

# Check XCom data
airflow tasks xcom-list <dag_id> <task_id> <execution_date>
```

### Database Connection Issues

#### PostgreSQL Connection Failures
**Error**: `psycopg2.OperationalError: could not connect to server`
**Solutions**:
```bash
# Test connectivity
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  nc -zv postgres.data-storage.svc.cluster.local 5432

# Check DNS resolution
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  nslookup postgres.data-storage.svc.cluster.local

# Verify credentials
kubectl get secret postgres-secret -n data-storage -o yaml

# Check PostgreSQL logs
kubectl logs postgres-0 -n data-storage
```

#### ClickHouse Connection Issues
**Error**: `requests.exceptions.ConnectionError`
**Solutions**:
```bash
# Test ClickHouse connectivity
kubectl exec -it airflow-scheduler-0 -n data-pipeline -- \
  curl -v http://clickhouse.data-storage.svc.cluster.local:8123/ping

# Check ClickHouse service
kubectl get svc clickhouse -n data-storage

# Verify ClickHouse is running
kubectl get pods -l app=clickhouse -n data-storage
```

### dbt Issues

#### dbt Connection Errors
**Error**: `Database Error in model 'model_name'`
**Solutions**:
```bash
# Test dbt connection
dbt debug --project-dir /opt/airflow/dbt

# Check profiles.yml
cat /opt/airflow/dbt/profiles.yml

# Verify environment variables
env | grep -E "(POSTGRES|SNOWFLAKE)"

# Test specific model
dbt run --select model_name --project-dir /opt/airflow/dbt
```

#### dbt Compilation Errors
**Error**: `Compilation Error in model 'model_name'`
**Solutions**:
```bash
# Compile without running
dbt compile --project-dir /opt/airflow/dbt

# Check compiled SQL
cat /opt/airflow/dbt/target/compiled/model_name.sql

# Validate SQL syntax
dbt parse --project-dir /opt/airflow/dbt
```

## Performance Issues

### Slow Pipeline Execution
**Symptoms**: Pipelines taking longer than expected
**Diagnostic Steps**:
```bash
# Check resource usage
kubectl top pods -n data-pipeline
kubectl top nodes

# Monitor database performance
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT * FROM pg_stat_activity;"

# Check for long-running queries
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT query, state, query_start FROM pg_stat_activity WHERE state = 'active';"
```

### Memory Issues
**Symptoms**: Pods getting OOMKilled
**Solutions**:
```bash
# Check memory limits
kubectl describe pod airflow-scheduler-0 -n data-pipeline

# Increase memory limits
kubectl patch deployment airflow-scheduler -n data-pipeline -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"airflow-scheduler","resources":{"limits":{"memory":"4Gi"}}}]}}}}'

# Monitor memory usage over time
kubectl top pod airflow-scheduler-0 -n data-pipeline --containers
```

## Data Quality Issues

### Missing Data
**Symptoms**: Expected data not appearing in target tables
**Investigation Steps**:
```sql
-- Check source data freshness
SELECT 
    MAX(created_at) as latest_record,
    COUNT(*) as total_records
FROM source_table;

-- Check transformation logic
SELECT COUNT(*) FROM staging_table;
SELECT COUNT(*) FROM intermediate_table;
SELECT COUNT(*) FROM marts_table;

-- Verify data pipeline execution
SELECT * FROM airflow.dag_run 
WHERE dag_id = 'data_pipeline_main' 
ORDER BY execution_date DESC LIMIT 5;
```

### Data Quality Failures
**Symptoms**: dbt tests failing
**Solutions**:
```bash
# Run specific test
dbt test --select test_name --project-dir /opt/airflow/dbt

# Check test results
dbt test --store-failures --project-dir /opt/airflow/dbt

# Investigate failed records
SELECT * FROM test_failures_table;
```

## Kubernetes Issues

### Pod Startup Problems
**Symptoms**: Pods stuck in Pending/CrashLoopBackOff
**Solutions**:
```bash
# Check pod status
kubectl describe pod <pod-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check resource constraints
kubectl describe nodes

# Check image pull issues
kubectl get pods -n <namespace> -o wide
```

### Service Discovery Issues
**Symptoms**: Services can't reach each other
**Solutions**:
```bash
# Check service endpoints
kubectl get endpoints -n <namespace>

# Test service connectivity
kubectl exec -it <pod-name> -n <namespace> -- \
  nc -zv <service-name>.<namespace>.svc.cluster.local <port>

# Check network policies
kubectl get networkpolicies -n <namespace>
```

## Monitoring and Alerting

### Missing Metrics
**Symptoms**: Dashboards showing no data
**Solutions**:
```bash
# Check Prometheus targets
kubectl port-forward svc/prometheus 9090:9090 -n monitoring
# Visit http://localhost:9090/targets

# Verify metric endpoints
curl http://<service-ip>:8080/metrics

# Check Grafana data sources
kubectl port-forward svc/grafana 3000:3000 -n monitoring
```

### Alert Fatigue
**Symptoms**: Too many false positive alerts
**Solutions**:
```yaml
# Adjust alert thresholds
- alert: HighMemoryUsage
  expr: (container_memory_usage / container_memory_limit) > 0.85  # Increased from 0.8
  for: 10m  # Increased from 5m
```

## Security Issues

### Authentication Failures
**Symptoms**: Unable to access services
**Solutions**:
```bash
# Check RBAC permissions
kubectl auth can-i <verb> <resource> --as=<user>

# Verify service account
kubectl get serviceaccount -n <namespace>

# Check secrets
kubectl get secrets -n <namespace>
```

### Certificate Issues
**Symptoms**: TLS/SSL connection errors
**Solutions**:
```bash
# Check certificate expiration
kubectl get certificates -n <namespace>

# Verify cert-manager
kubectl get certificaterequests -n <namespace>

# Check ingress TLS
kubectl describe ingress <ingress-name> -n <namespace>
```

## Emergency Procedures

### Pipeline Failure Recovery
```bash
# 1. Stop current pipeline runs
airflow dags pause data_pipeline_main

# 2. Check system health
kubectl get pods -A | grep -v Running

# 3. Review recent changes
git log --oneline -10

# 4. Rollback if necessary
kubectl rollout undo deployment/airflow-scheduler -n data-pipeline

# 5. Restart pipeline
airflow dags unpause data_pipeline_main
airflow dags trigger data_pipeline_main
```

### Data Corruption Recovery
```bash
# 1. Stop all data processing
kubectl scale deployment airflow-scheduler --replicas=0 -n data-pipeline

# 2. Assess damage
psql -U postgres -c "SELECT COUNT(*) FROM affected_table;"

# 3. Restore from backup
pg_restore -U postgres -d database_name backup_file.dump

# 4. Verify data integrity
dbt test --project-dir /opt/airflow/dbt

# 5. Resume operations
kubectl scale deployment airflow-scheduler --replicas=1 -n data-pipeline
```

## Useful Commands Reference

### Kubernetes Debugging
```bash
# Get all resources in namespace
kubectl get all -n data-pipeline

# Check resource usage
kubectl top pods -n data-pipeline
kubectl top nodes

# View logs with follow
kubectl logs -f deployment/airflow-scheduler -n data-pipeline

# Execute commands in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Port forward for local access
kubectl port-forward svc/airflow-webserver 8080:8080 -n data-pipeline
```

### Database Debugging
```bash
# PostgreSQL
kubectl exec -it postgres-0 -n data-storage -- psql -U postgres

# ClickHouse
kubectl exec -it clickhouse-0 -n data-storage -- clickhouse-client

# Check database connections
kubectl exec -it postgres-0 -n data-storage -- \
  psql -U postgres -c "SELECT * FROM pg_stat_activity;"
```

### Airflow Debugging
```bash
# List DAGs
airflow dags list

# Test DAG
airflow dags test <dag_id> <execution_date>

# Check connections
airflow connections list

# View task logs
airflow tasks log <dag_id> <task_id> <execution_date>
```