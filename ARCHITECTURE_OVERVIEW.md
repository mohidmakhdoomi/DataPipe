# Data Pipeline Architecture Overview

This document provides a comprehensive analysis of our enterprise data pipeline architecture, including detailed technology specifications and integration patterns.

## 🏗️ **Complete Architecture Overview**

Our data pipeline implements a **modern, cloud-native, event-driven architecture** that processes high-volume e-commerce data in real-time. The system follows a **Lambda Architecture** pattern with both batch and streaming processing capabilities.

### **Data Flow Architecture:**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Data Generator │───▶│      Kafka      │───▶│   ClickHouse    │───▶│   Analytics     │
│  (120 evt/min)  │    │  (3 partitions) │    │  (Real-time)    │    │   Dashboard     │
└─────────────────┘    └─────────────────┘    └─────────────────┘    └─────────────────┘
                                │
                                ▼
                       ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
                       │  Kafka Connect  │───▶│       S3        │───▶│     Spark       │
                       │  (S3 Sink)      │    │  (Data Lake)    │    │ (Batch Process) │
                       └─────────────────┘    └─────────────────┘    └─────────────────┘
                                                        │                       │
                                                        │                       ▼
                                                        │              ┌─────────────────┐
                                                        │              │   Snowflake     │
                                                        │              │ (Data Warehouse)│
                                                        │              └─────────────────┘
                                                        ▼                       │
                                               ┌─────────────────┐              ▼
                                               │      dbt        │     ┌─────────────────┐
                                               │ (Transformations)│     │   Final Models  │
                                               └─────────────────┘     └─────────────────┘
```

### **Infrastructure Layers:**
- **Orchestration**: Airflow (workflow management)
- **Containerization**: Docker + Kubernetes (EKS)
- **Infrastructure**: Terraform (AWS resources)
- **Storage**: PostgreSQL (transactional), S3 (data lake), Snowflake (warehouse)
- **Streaming**: Kafka (event streaming)
- **Processing**: Spark (batch processing), ClickHouse (real-time analytics)
- **Transformation**: dbt (SQL transformations), Spark (complex ETL)

---

## 📊 **Technology Analysis**

### **1. Snowflake**
- **Type of System**: Cloud Data Warehouse / Data Platform
- **Cloud Computing Model**: Software as a Service (SaaS)
- **Interfaces with**:
  - **dbt** → Transformation relationship: dbt connects to Snowflake to execute SQL transformations and build data models
  - **S3** → Data ingestion relationship: Snowflake ingests data from S3 buckets via COPY commands or Snowpipe
  - **Airflow** → Orchestration relationship: Airflow schedules and manages Snowflake data loading and transformation jobs
  - **AWS** → Infrastructure relationship: Runs on AWS infrastructure but managed by Snowflake

### **2. Docker**
- **Type of System**: Containerization Platform
- **Cloud Computing Model**: Not applicable (containerization technology)
- **Interfaces with**:
  - **Kubernetes** → Container orchestration relationship: Kubernetes orchestrates Docker containers across clusters
  - **Airflow** → Containerization relationship: Airflow components run in Docker containers for isolation and scalability
  - **dbt** → Containerization relationship: dbt runs in Docker containers for consistent execution environments
  - **ClickHouse** → Containerization relationship: ClickHouse database runs in Docker containers
  - **Kafka** → Containerization relationship: Kafka brokers and tools run in Docker containers
  - **Terraform** → Infrastructure relationship: Terraform provisions infrastructure where Docker containers are deployed

### **3. Airflow**
- **Type of System**: Workflow Orchestration / Data Pipeline Management
- **Cloud Computing Model**: Can be deployed as IaaS, PaaS, or managed service
- **Interfaces with**:
  - **dbt** → Orchestration relationship: Airflow schedules and triggers dbt transformations as part of data pipelines
  - **Snowflake** → Data orchestration relationship: Airflow manages data loading, transformation, and quality checks in Snowflake
  - **Docker** → Containerization relationship: Airflow runs in Docker containers for scalability and environment consistency
  - **Kubernetes** → Orchestration relationship: Kubernetes manages Airflow scheduler, webserver, and worker pods
  - **AWS** → Infrastructure relationship: Airflow accesses AWS services (S3, RDS, Secrets Manager) for data operations
  - **Kafka** → Pipeline relationship: Airflow can trigger Kafka-based streaming jobs and monitor Kafka topics

### **4. dbt**
- **Type of System**: Data Transformation / Analytics Engineering Platform
- **Cloud Computing Model**: Can be SaaS (dbt Cloud) or self-hosted
- **Interfaces with**:
  - **Snowflake** → Transformation relationship: dbt connects to Snowflake to execute SQL transformations and build dimensional models
  - **Airflow** → Orchestration relationship: Airflow schedules dbt runs and manages transformation dependencies
  - **Docker** → Containerization relationship: dbt runs in Docker containers for consistent execution environments
  - **Kubernetes** → Orchestration relationship: Kubernetes runs dbt jobs as pods or cron jobs

### **5. Kubernetes**
- **Type of System**: Container Orchestration Platform
- **Cloud Computing Model**: Infrastructure as a Service (IaaS) when using managed services like EKS
- **Interfaces with**:
  - **Docker** → Container orchestration relationship: Kubernetes orchestrates Docker containers with scaling, networking, and service discovery
  - **Terraform** → Infrastructure relationship: Terraform provisions EKS clusters and Kubernetes resources
  - **AWS** → Infrastructure relationship: Runs on AWS EKS with integration to AWS services (IAM, VPC, EBS, ECR)
  - **Airflow** → Orchestration relationship: Kubernetes manages Airflow components (scheduler, webserver, workers) as deployments
  - **Kafka** → Service orchestration relationship: Kubernetes manages Kafka brokers as StatefulSets with persistent storage
  - **ClickHouse** → Database orchestration relationship: Kubernetes manages ClickHouse instances with persistent volumes

### **6. Terraform**
- **Type of System**: Infrastructure as Code (IaC) / Cloud Provisioning
- **Cloud Computing Model**: Not applicable (infrastructure provisioning tool)
- **Interfaces with**:
  - **AWS** → Infrastructure provisioning relationship: Terraform creates and manages AWS resources (EKS, RDS, MSK, S3, VPC)
  - **Kubernetes** → Infrastructure relationship: Terraform provisions EKS clusters where Kubernetes workloads run
  - **Docker** → Infrastructure relationship: Terraform provisions infrastructure where Docker containers are deployed

### **7. ClickHouse**
- **Type of System**: Columnar Database / Real-time Analytics Database
- **Cloud Computing Model**: Can be self-hosted (IaaS) or managed service (PaaS)
- **Interfaces with**:
  - **Kafka** → Real-time ingestion relationship: ClickHouse consumes data directly from Kafka topics using Kafka engine tables and materialized views
  - **Docker** → Containerization relationship: ClickHouse runs in Docker containers for deployment consistency
  - **Kubernetes** → Orchestration relationship: Kubernetes manages ClickHouse deployments with persistent storage and service discovery

### **8. Kafka**
- **Type of System**: Distributed Event Streaming Platform
- **Cloud Computing Model**: Can be self-hosted (IaaS) or managed service (PaaS) like MSK
- **Interfaces with**:
  - **ClickHouse** → Real-time data relationship: Kafka streams data to ClickHouse for real-time analytics via Kafka engine tables
  - **Spark** → Data ingestion relationship: Spark reads from Kafka topics (via S3) for batch processing and complex transformations
  - **AWS** → Infrastructure relationship: Uses AWS MSK (managed Kafka) or runs on AWS infrastructure
  - **Docker** → Containerization relationship: Kafka brokers and tools run in Docker containers
  - **Kubernetes** → Orchestration relationship: Kubernetes manages Kafka as StatefulSets with persistent volumes and service discovery
  - **Airflow** → Pipeline relationship: Airflow can monitor Kafka topics and trigger downstream processing based on data availability

### **9. Apache Spark**
- **Type of System**: Distributed Computing Engine / Big Data Processing Framework
- **Cloud Computing Model**: Can be deployed as IaaS (self-managed) or PaaS (managed services like EMR, Databricks)
- **Interfaces with**:
  - **Kafka** → Data ingestion relationship: Spark reads data from S3 (populated by Kafka Connect) for batch processing
  - **S3** → Data lake relationship: Spark reads raw data from S3 and writes processed data back for Snowflake ingestion
  - **Snowflake** → Data preparation relationship: Spark prepares and transforms data before loading into Snowflake
  - **Airflow** → Orchestration relationship: Airflow schedules and manages Spark jobs as part of data pipelines
  - **Kubernetes** → Orchestration relationship: Kubernetes manages Spark driver and executor pods with auto-scaling
  - **Docker** → Containerization relationship: Spark runs in Docker containers for consistent deployment
  - **dbt** → Complementary relationship: Spark handles heavy ETL while dbt focuses on SQL transformations in the warehouse

### **10. AWS**
- **Type of System**: Cloud Computing Platform / Infrastructure Provider
- **Cloud Computing Model**: Infrastructure as a Service (IaaS), Platform as a Service (PaaS), Software as a Service (SaaS)
- **Interfaces with**:
  - **Terraform** → Infrastructure relationship: Terraform provisions and manages AWS resources (EKS, RDS, MSK, S3, VPC, IAM)
  - **Kubernetes** → Infrastructure relationship: AWS EKS provides managed Kubernetes control plane with integration to AWS services
  - **Snowflake** → Infrastructure relationship: Snowflake runs on AWS infrastructure and integrates with AWS services
  - **Kafka** → Infrastructure relationship: AWS MSK provides managed Kafka service
  - **Spark** → Infrastructure relationship: AWS provides S3 for data storage and EKS for Spark cluster orchestration
  - **Airflow** → Infrastructure relationship: Airflow accesses AWS services (S3 for data, Secrets Manager for credentials, RDS for metadata)
  - **Docker** → Infrastructure relationship: AWS provides container registry (ECR) and compute resources for Docker containers

---

## 🔄 **Key Integration Patterns**

### **Real-time Data Flow:**
1. **Data Generator** → **Kafka** (120 events/min + transactions)
2. **Kafka** → **ClickHouse** (real-time analytics via materialized views)
3. **Kafka** → **S3** (via Kafka Connect for data lake)

### **Batch Data Flow:**
1. **S3** → **Spark** (complex ETL processing and data quality)
2. **Spark** → **S3** (processed data for Snowflake ingestion)
3. **S3** → **Snowflake** (data warehouse loading)
4. **Snowflake** → **dbt** (SQL transformations and modeling)
5. **Airflow** orchestrates the entire batch pipeline

### **Infrastructure Management:**
1. **Terraform** provisions AWS infrastructure
2. **Kubernetes** orchestrates containerized applications
3. **Docker** provides consistent runtime environments

---

## 🎯 **Current Implementation Status**

### **✅ Fully Implemented & Working:**
- **Data Generator**: Real-time streaming (120 events/min + transactions)
- **Kafka**: 3-partition topics with auto-creation
- **Docker**: All services containerized including Spark
- **Kubernetes**: Production-ready manifests and deployment scripts including Spark cluster
- **Terraform**: Complete AWS infrastructure configuration
- **PostgreSQL**: Transactional database with proper schema
- **Spark**: Kubernetes-native batch processing with ETL jobs and data quality checks

### **⚠️ Partially Implemented:**
- **ClickHouse**: Tables created but stability issues
- **Airflow**: Configured but some health check issues
- **dbt**: Models created but not fully integrated

### **🔧 Ready for Configuration:**
- **Snowflake**: Environment variables prepared, needs credentials
- **AWS S3**: Terraform configuration ready, needs deployment
- **Kafka Connect**: Configuration prepared, needs service deployment

---

## 📋 **Deployment Readiness**

### **Production-Ready Components:**
- **Core Data Pipeline**: Kafka streaming working at 120 events/min
- **Container Infrastructure**: Docker + Kubernetes fully configured
- **AWS Infrastructure**: Terraform scripts for EKS, RDS, MSK, S3
- **Security**: Proper secrets management and IAM roles
- **Monitoring**: Health checks and resource limits configured

### **Next Steps for Full Deployment:**
1. **Deploy AWS Infrastructure**: Run Terraform to create EKS cluster
2. **Configure External Credentials**: Set up Snowflake and AWS credentials
3. **Deploy to Kubernetes**: Use deployment scripts to launch on EKS
4. **Set up Kafka Connect**: Add S3 sink connector for data lake
5. **Integrate dbt**: Connect to Snowflake for transformations

This architecture provides a robust, scalable, and modern data platform capable of handling both real-time streaming and batch processing workloads with enterprise-grade reliability and performance.