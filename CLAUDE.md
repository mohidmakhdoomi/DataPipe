# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a data pipeline project implementing a Lambda Architecture for high-throughput data processing (10,000 events/second target). The project integrates PostgreSQL, Kafka, AWS S3, Apache Iceberg, Spark, dbt Core, Snowflake, ClickHouse, and Airflow using Kubernetes (Kind) on Docker Desktop.

Current implementation phase: Data Ingestion Pipeline (PostgreSQL → Debezium CDC → Kafka → S3 Archival)

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

### Validation and Testing
```bash
# Run cluster validation
kubectl apply -f test-validation.yaml
kubectl logs job/cluster-validation

# Test storage persistence
kubectl apply -f storage-canary-test.yaml
kubectl logs job/storage-canary-test

# Validate storage persistence
kubectl apply -f storage-persistence-validation.yaml
kubectl logs job/storage-persistence-validation
```

## Architecture Overview

### Current Status
Currently working on the data-ingestion-pipeline spec, the requirements, design and tasks are located in directory `.kiro/specs/data-ingestion-pipeline/`
- **Completed**: Tasks 1-2 (Kind cluster setup, persistent volume provisioning) 
- **Next Task**: Task 3 (Kubernetes namespaces and RBAC)
- **Constraint**: 4GB total RAM allocation for entire ingestion pipeline

### Resource Allocation Strategy
- Kubernetes overhead: ~622MB
- Available for workloads: ~3.4GB
- Component budgets:
  - PostgreSQL: 400-500MB
  - Kafka: 2GB (3 brokers)
  - Schema Registry: 400MB
  - Debezium: 300MB

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
- `kind-config.yaml` - Single-node Kind cluster configuration
- `storage-classes.yaml` - Differentiated storage classes for workload types
- `data-services-pvcs.yaml` - Persistent volume claims for all services

### Additional Documentation
- `kiro.md` - Kiro Project memory and status tracking
- `task1-validation-report.md` - Cluster setup validation
- `task2-storage-provisioning-report.md` - Storage provisioning validation

### Validation Scripts
- `test-validation.yaml` - Cluster health validation
- `storage-canary-test.yaml` - Storage performance testing
- `storage-persistence-validation.yaml` - Data persistence validation

## Development Approach

This project uses a multi-model consensus approach for complex decisions, validated across multiple AI models (Gemini, Opus, Grok, O3). Implementation follows a phased approach with comprehensive validation at each step.

### Key Principles
1. Resource efficiency within 4GB constraint
2. Production parity through Kubernetes-native approach
3. Incremental deployment to prevent resource exhaustion
4. Comprehensive validation before integration
5. Clear migration path to production environments