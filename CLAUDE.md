# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a data pipeline project implementing a Lambda Architecture for high-throughput data processing (10,000 events/second target). The project integrates PostgreSQL, Kafka, AWS S3, Apache Iceberg, Spark, dbt Core, Snowflake, ClickHouse, and Airflow using Kubernetes (Kind) on Docker Desktop.

Current implementation phase: Data Ingestion Pipeline (PostgreSQL → Debezium CDC → Kafka → S3 Archival)

**Task Progress**: Tasks 1-5 completed ✅ | Currently on Task 6 (Schema Registry)

## Key Commands

### Kubernetes Cluster Management
```bash
# Create Kind cluster
kind create cluster --config kind-config.yaml

# Delete cluster
kind delete cluster --name data-ingestion

# Check cluster status
kubectl cluster-info --context kind-data-ingestion
kubectl get nodes
kubectl get pods --all-namespaces

# Get resources in data-ingestion namespace
kubectl get all -n data-ingestion
kubectl get pvc -n data-ingestion
```

### Storage and Persistent Volumes
```bash
# Apply storage classes
kubectl apply -f storage-classes.yaml

# Create persistent volume claims
kubectl apply -f data-services-pvcs.yaml

# Check storage status
kubectl get storageclass
kubectl get pvc
kubectl get pv
```

### Service Deployments
```bash
# Deploy PostgreSQL (Task 4)
kubectl apply -f task4-postgresql-configmap.yaml
kubectl apply -f task4-postgresql-statefulset.yaml

# Deploy Kafka (Task 5)
kubectl apply -f task5-kafka-kraft-3brokers.yaml
kubectl apply -f task5-cdc-topics-job.yaml

# Check service status
kubectl get statefulset -n data-ingestion
kubectl get pods -n data-ingestion -l app=postgresql
kubectl get pods -n data-ingestion -l app=kafka
```

## Architecture Overview

### Current Status
Currently working on the data-ingestion-pipeline spec, the requirements, design and tasks are located in directory `.kiro/specs/data-ingestion-pipeline/`
- **Completed**: Tasks 1-5 ✅
  - Task 1: Kind cluster setup
  - Task 2: Persistent volume provisioning
  - Task 3: Kubernetes namespaces and RBAC
  - Task 4: PostgreSQL deployment with CDC
  - Task 5: 3-broker Kafka cluster with KRaft
- **Current Task**: Task 6 (Confluent Schema Registry)
- **Constraint**: 4GB total RAM allocation for data ingestion pipeline (out of 24GB total system allocation)

### Resource Allocation Strategy
- **System Total**: 24GB RAM, 10 CPU cores, 1TB storage
- **Data Ingestion Pipeline**: 4GB RAM allocation
  - Kubernetes overhead: ~622MB
  - Available for workloads: ~3.4GB
  - Component budgets:
    - PostgreSQL: 1GB
    - Kafka: 2GB (3 brokers with HA)
    - Schema Registry: 512MB
    - Kafka Connect/Debezium: 512MB

### Storage Architecture
- Three differentiated storage classes: database-local-path, streaming-local-path, metadata-local-path
- Total allocation: 16.5Gi (PostgreSQL 5Gi + Kafka 10Gi + Schema Registry 512Mi + Kafka Connect 1Gi)
- Reclaim policy: Retain (prevents data loss in development)
- Volume binding: WaitForFirstConsumer (optimal pod placement)

### Port Mappings
- PostgreSQL: localhost:5432 → 30432
- Kafka: localhost:9092 → 30092
- Schema Registry: localhost:8081 → 30081
- Kafka Connect: localhost:8083 → 30083

## Important Files

### Requirements Design and Tasks

- `.kiro/specs/data-ingestion-pipeline/requirements.md` - Requirements
- `.kiro/specs/data-ingestion-pipeline/design.md` - Architecture design
- `.kiro/specs/data-ingestion-pipeline/tasks.md` - Implementation tasks

### Configuration Files
- `kind-config.yaml` - 3-node Kind cluster (1 control-plane + 2 workers) configuration
- `01-namespace.yaml` - Data ingestion namespace
- `02-service-accounts.yaml` - Service accounts for components
- `03-network-policies.yaml` - Network isolation policies
- `04-secrets.yaml` - Secret management
- `storage-classes.yaml` - Differentiated storage classes for workload types
- `data-services-pvcs.yaml` - Persistent volume claims for all services
- `task4-postgresql-configmap.yaml` - PostgreSQL configuration
- `task4-postgresql-statefulset.yaml` - PostgreSQL deployment
- `task5-kafka-kraft-3brokers.yaml` - Kafka cluster deployment
- `task5-cdc-topics-job.yaml` - CDC topics creation

### Additional Documentation
- `kiro.md` - Kiro Project memory and status tracking
- `task1-validation-report.md` - Cluster setup validation
- `task2-storage-provisioning-report.md` - Storage provisioning validation
- `task3-completion-report.md` - Namespace and RBAC setup report

### Validation Scripts
- `test-validation.yaml` - Cluster health validation
- `storage-canary-test.yaml` - Storage performance testing
- `storage-persistence-validation.yaml` - Data persistence validation
- `task3-validation.yaml` - Namespace and RBAC validation

### Key Principles
1. Resource efficiency within 4GB constraint for data ingestion
2. Production parity through Kubernetes-native approach
3. Incremental deployment to prevent resource exhaustion
4. Comprehensive validation before integration
5. Clear migration path to production environments
6. Prefer out-of-the-box solutions over custom coding
7. External cloud services (S3, Snowflake) not emulated locally
8. Spark runs on Kubernetes, not standalone
9. Airflow DAGs separated from services container