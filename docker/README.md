# Docker Containers for Data Pipeline

This directory contains Docker configurations for all services in our enterprise data pipeline.

## Container Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Airflow   │  │     dbt     │  │     ClickHouse      │ │
│  │ Scheduler   │  │ Transform   │  │   Analytics DB      │ │
│  │  Webserver  │  │   Runner    │  │                     │ │
│  │   Worker    │  │             │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Kafka     │  │    Data     │  │      Jupyter        │ │
│  │  Producer   │  │ Generator   │  │    Notebooks        │ │
│  │  Consumer   │  │             │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Services

- **airflow/** - Apache Airflow for orchestration
- **dbt/** - dbt for data transformations  
- **clickhouse/** - ClickHouse for real-time analytics
- **kafka-tools/** - Kafka producers and consumers
- **data-generator/** - Our data generation service
- **jupyter/** - Jupyter notebooks for analysis
- **base/** - Base images with common dependencies

## Quick Start

Build all containers:
```bash
docker-compose build
```

Run the entire stack:
```bash
docker-compose up -d
```

## Individual Services

Each service can be built and run independently:
```bash
cd airflow/
docker build -t data-pipeline/airflow .
docker run -d data-pipeline/airflow
```