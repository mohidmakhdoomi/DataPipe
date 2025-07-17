# Airflow Docker Configuration

This directory contains the Docker-based Airflow setup for the data pipeline project, optimized for Kubernetes deployment with Snowflake integration.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │   ClickHouse    │    │   Snowflake     │
│   (Source)      │    │  (Real-time)    │    │ (Data Warehouse)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │     Airflow     │
                    │   (Orchestrator)│
                    └─────────────────┘
                                 │
                    ┌─────────────────┐
                    │       dbt       │
                    │ (Transformations)│
                    └─────────────────┘
```

## Key Features

- **Environment-aware configuration**: Automatically detects Kubernetes vs local deployment
- **Snowflake-first approach**: Prioritizes Snowflake as the primary data warehouse
- **Comprehensive monitoring**: Built-in data quality and pipeline monitoring
- **Scalable architecture**: Designed for production Kubernetes deployment

## DAGs Overview

### Primary DAGs (Production-Ready)

1. **`data_pipeline_main`** - Main orchestration DAG
   - Hourly execution
   - Environment-aware (PostgreSQL → Snowflake)
   - Comprehensive data quality checks
   - Real-time ClickHouse updates

2. **`snowflake_pipeline`** - Snowflake-focused pipeline
   - Daily execution
   - Direct Snowflake integration
   - Optimized for cloud data warehouse

3. **`pipeline_monitoring`** - Comprehensive monitoring
   - 15-minute intervals
   - SLA compliance tracking
   - Automated alerting

4. **`data_quality_monitoring`** - Data quality focus
   - 6-hour intervals
   - Detailed profiling and validation

### Supporting DAGs

5. **`data_backfill`** - Historical data processing
6. **`maintenance_operations`** - System maintenance tasks

## Environment Configuration

### Local Development
```bash
# Use local docker-compose services
POSTGRES_HOST=postgres-data
CLICKHOUSE_HOST=clickhouse
AIRFLOW_ENV=development
```

### Kubernetes Production
```bash
# Use Kubernetes service names
POSTGRES_HOST=postgres.data-storage.svc.cluster.local
CLICKHOUSE_HOST=clickhouse.data-storage.svc.cluster.local
AIRFLOW_ENV=production
```

### Snowflake Integration
```bash
SNOWFLAKE_ACCOUNT=your-account
SNOWFLAKE_USER=your-user
SNOWFLAKE_PASSWORD=your-password
SNOWFLAKE_ROLE=your-role
SNOWFLAKE_DATABASE=your-database
SNOWFLAKE_WAREHOUSE=your-warehouse
```

## Deployment

### Docker Build
```bash
cd docker
docker build -t data-pipeline/airflow:latest airflow/
```

### Kubernetes Deployment
```bash
kubectl apply -f ../k8s/airflow/
```

### Local Testing
```bash
cd airflow
docker-compose up -d
```

## Configuration Files

- **`Dockerfile`**: Multi-stage build with dbt integration
- **`requirements.txt`**: Python dependencies with Snowflake support
- **`config/`**: Airflow configuration and logging setup
- **`plugins/`**: Custom operators and hooks
- **`.env.example`**: Environment variable templates

## Monitoring & Alerting

The pipeline includes comprehensive monitoring:

- **Data Freshness**: Tracks data recency across sources
- **Pipeline Performance**: DAG execution metrics and SLA tracking
- **Data Quality**: Automated validation and profiling
- **System Health**: Resource utilization and service availability

## Best Practices

1. **Environment Variables**: All configuration via environment variables
2. **Secrets Management**: Use Airflow Variables/Connections for sensitive data
3. **Error Handling**: Comprehensive logging and error recovery
4. **Scalability**: Designed for horizontal scaling in Kubernetes
5. **Monitoring**: Built-in observability and alerting

## Troubleshooting

### Common Issues

1. **Connection Errors**: Check service names and network connectivity
2. **dbt Failures**: Verify target configuration and credentials
3. **Memory Issues**: Adjust resource limits in Kubernetes
4. **Snowflake Timeouts**: Check warehouse size and query complexity

### Debugging

```bash
# Check DAG logs
kubectl logs -f deployment/airflow-scheduler -n data-pipeline

# Verify connections
airflow connections list

# Test DAG
airflow dags test data_pipeline_main 2024-01-01
```

## Security Considerations

- All credentials stored in Airflow Variables/Connections
- Network policies restrict inter-service communication
- RBAC configured for multi-tenant access
- Audit logging enabled for compliance

## Performance Optimization

- Connection pooling for database access
- Parallel task execution where possible
- Resource limits and requests configured
- Caching strategies for repeated operations