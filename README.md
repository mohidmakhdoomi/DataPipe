# Enterprise Data Pipeline Project

A comprehensive end-to-end data pipeline showcasing enterprise-grade data engineering practices.

## Tech Stack
- **Orchestration**: Apache Airflow on Kubernetes
- **Transformations**: dbt
- **Data Warehouse**: Snowflake
- **Real-time Analytics**: ClickHouse
- **Streaming**: Apache Kafka (AWS MSK)
- **Cloud**: AWS (S3, EKS, RDS)
- **Containerization**: Docker + Kubernetes

## Data Domain
User transaction system covering:
- User profiles and behavior
- Product catalog and transactions
- Real-time events and sessions
- Support interactions

## Project Structure
```
├── data-generators/    # Mock data sources
├── airflow/           # DAGs and orchestration
├── dbt/              # Data transformations
├── kafka/            # Streaming components
├── clickhouse/       # Real-time analytics
├── docker/           # Container definitions
├── k8s/              # Kubernetes manifests
└── terraform/        # AWS infrastructure
```

## Getting Started
1. Generate mock data with realistic patterns
2. Set up local development environment
3. Deploy infrastructure components
4. Build and test data pipeline