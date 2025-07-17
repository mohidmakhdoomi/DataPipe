# Kubernetes Deployment for Data Pipeline

This directory contains Kubernetes manifests to deploy our enterprise data pipeline on EKS.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Cluster                              │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │   Namespace:    │    │        Namespace:               │ │
│  │  data-pipeline  │    │     data-pipeline-system       │ │
│  │                 │    │                                 │ │
│  │  ┌───────────┐  │    │  ┌─────────────────────────────┐ │ │
│  │  │ Airflow   │  │    │  │      Monitoring             │ │ │
│  │  │ Scheduler │  │    │  │   - Prometheus              │ │ │
│  │  │ Webserver │  │    │  │   - Grafana                 │ │ │
│  │  │ Worker    │  │    │  │   - Logging                 │ │ │
│  │  └───────────┘  │    │  └─────────────────────────────┘ │ │
│  │                 │    └─────────────────────────────────┘ │
│  │  ┌───────────┐  │                                        │
│  │  │    dbt    │  │    ┌─────────────────────────────────┐ │
│  │  │Transform  │  │    │        Namespace:               │ │
│  │  └───────────┘  │    │      data-storage               │ │
│  │                 │    │                                 │ │
│  │  ┌───────────┐  │    │  ┌─────────────────────────────┐ │ │
│  │  │ClickHouse │  │    │  │      PostgreSQL             │ │ │
│  │  │Analytics  │  │    │  │      StatefulSet            │ │ │
│  │  └───────────┘  │    │  └─────────────────────────────┘ │ │
│  │                 │    │                                 │ │
│  │  ┌───────────┐  │    │  ┌─────────────────────────────┐ │ │
│  │  │   Kafka   │  │    │  │         Kafka               │ │ │
│  │  │  Tools    │  │    │  │      StatefulSet            │ │ │
│  │  └───────────┘  │    │  └─────────────────────────────┘ │ │
│  │                 │    └─────────────────────────────────┘ │
│  │  ┌───────────┐  │                                        │
│  │  │   Data    │  │                                        │
│  │  │Generator  │  │                                        │
│  │  └───────────┘  │                                        │
│  └─────────────────┘                                        │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
k8s/
├── namespaces/          # Namespace definitions
├── storage/             # PVCs and storage classes
├── databases/           # PostgreSQL, ClickHouse
├── kafka/               # Kafka cluster
├── airflow/             # Airflow components
├── dbt/                 # dbt jobs
├── data-generator/      # Data generation service
├── monitoring/          # Prometheus, Grafana
├── ingress/             # Load balancers and ingress
├── secrets/             # Secret management
├── configmaps/          # Configuration
└── scripts/             # Deployment helpers
```

## Quick Start

1. **Connect to EKS cluster:**
   ```bash
   aws eks update-kubeconfig --region us-west-2 --name data-pipeline-dev-cluster
   ```

2. **Deploy infrastructure:**
   ```bash
   kubectl apply -f namespaces/
   kubectl apply -f storage/
   kubectl apply -f secrets/
   kubectl apply -f configmaps/
   ```

3. **Deploy data services:**
   ```bash
   kubectl apply -f databases/
   kubectl apply -f kafka/
   ```

4. **Deploy pipeline components:**
   ```bash
   kubectl apply -f airflow/
   kubectl apply -f dbt/
   kubectl apply -f data-generator/
   ```

5. **Deploy monitoring:**
   ```bash
   kubectl apply -f monitoring/
   kubectl apply -f ingress/
   ```

## Access Services

- **Airflow UI**: `kubectl port-forward svc/airflow-webserver 8080:8080`
- **ClickHouse**: `kubectl port-forward svc/clickhouse 8123:8123`
- **Grafana**: `kubectl port-forward svc/grafana 3000:3000`

## Scaling

Scale individual components:
```bash
kubectl scale deployment airflow-worker --replicas=5
kubectl scale deployment kafka-tools --replicas=3
```