# Enterprise Data Pipeline Project

A comprehensive, production-ready data pipeline implementing modern data engineering best practices with enterprise-grade security, monitoring, and scalability.

## Overview

This project demonstrates a complete data engineering solution that processes high-volume e-commerce data through both real-time streaming and batch processing workflows. The architecture follows a Lambda pattern with cloud-native, containerized services orchestrated on Kubernetes.

## Architecture

### Data Flow
```
Data Generator → Kafka → ClickHouse (Real-time Analytics)
     ↓              ↓
     ↓         Kafka Connect → S3 → Spark → Snowflake → dbt → Analytics
     ↓
PostgreSQL (Transactional Data)
```

### Technology Stack
- **Orchestration**: Apache Airflow on Kubernetes
- **Data Transformation**: dbt (SQL) + Apache Spark (Complex ETL)
- **Data Warehouse**: Snowflake (Production) / PostgreSQL (Development)
- **Real-time Analytics**: ClickHouse
- **Event Streaming**: Apache Kafka (AWS MSK)
- **Cloud Platform**: AWS (S3, EKS, RDS, MSK)
- **Infrastructure**: Terraform + Kubernetes + Docker
- **Monitoring**: Comprehensive observability with SLA tracking

## Project Structure

```
├── airflow/                       # Airflow DAGs and configuration
├── data-generators/               # Real-time data generation (120 events/min)
├── dbt/                           # SQL transformations and data modeling
├── docker/                        # Production containerization
│   └── compose files              # Multi-service orchestration
├── k8s/                           # Kubernetes manifests and deployment
├── scripts/                        # Helper scripts
│   ├── start-docker.ps1          # Start environment
│   ├── stop-docker.ps1           # Stop environment
├── terraform/                     # AWS infrastructure as code
└── .kiro/steering/                # Project standards and guidelines
```

## Data Domain

**E-commerce Transaction System**:
- **User Management**: Profiles, preferences, and behavioral analytics
- **Product Catalog**: Inventory, pricing, and categorization
- **Transaction Processing**: Orders, payments, and fulfillment
- **Real-time Events**: User sessions, clicks, and interactions
- **Customer Support**: Tickets, interactions, and resolution tracking

## Key Features

### Production-Ready Components
- **Security**: No hardcoded secrets, comprehensive RBAC, data encryption
- **Scalability**: Kubernetes-native with auto-scaling capabilities
- **Monitoring**: SLA tracking, data quality validation, system health checks
- **Environment Management**: Development, staging, and production configurations
- **CI/CD Ready**: Infrastructure as code with automated deployment

### Data Processing Capabilities
- **Real-time Streaming**: 120+ events per minute with sub-second latency
- **Batch Processing**: Complex ETL with data quality validation
- **Data Quality**: Automated profiling, validation, and anomaly detection
- **Transformation**: SQL-first approach with dbt + Spark for complex operations

## Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.9+
- kubectl (for Kubernetes deployment)
- Terraform (for AWS infrastructure)

### Local Development Setup

1. **Clone and Setup Environment**
   ```bash
   git clone <repository-url>
   cd enterprise-data-pipeline
   ```

2. **Configure Security**
   ```bash
   # Copy environment template
   cp docker/.env.example docker/.env
   
   # Generate secure passwords (see SECURITY_SETUP.md)
   # Edit docker/.env with your secure credentials
   ```

3. **Start All Services**
   ```powershell
   scripts/start-docker.ps1
   ```

4. **Access Airflow**
   ```bash   
   # Access UI at http://localhost:8080
   # Default: admin/admin (change in production)
   ```

### Production Deployment

1. **Deploy AWS Infrastructure**
   ```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Configure Kubernetes**
   ```bash
   # Update kubeconfig for EKS
   aws eks update-kubeconfig --name data-pipeline-cluster
   
   # Deploy secrets and services
   kubectl apply -f k8s/secrets/
   kubectl apply -f k8s/
   ```

3. **Verify Deployment**
   ```bash
   # Check service health
   kubectl get pods -n data-pipeline
   
   # Access Airflow UI via LoadBalancer
   kubectl get svc airflow-webserver -n data-pipeline
   ```

## Configuration

### Environment Variables
All sensitive configuration is managed through environment variables. See:
- **[Environment Files Guide](ENV_FILES_GUIDE.md)** - Complete variable reference
- **[Security Setup](SECURITY_SETUP.md)** - Security configuration guide

### Key Configuration Files
- `docker/.env` - Local development configuration
- `docker/airflow/.env` - Production Airflow configuration
- `k8s/secrets/` - Kubernetes secrets management
- `terraform/variables.tf` - Infrastructure configuration

## Documentation

### Architecture & Design
- **[Architecture Overview](ARCHITECTURE_OVERVIEW.md)** - Complete system architecture
- **[Project Standards](.kiro/steering/project-standards.md)** - Development guidelines
- **[Security Guidelines](.kiro/steering/security-guidelines.md)** - Security requirements

### Operational Guides
- **[Deployment Guide](.kiro/steering/deployment-guide.md)** - Step-by-step deployment
- **[Monitoring Standards](.kiro/steering/monitoring-standards.md)** - Observability setup
- **[Troubleshooting Guide](.kiro/steering/troubleshooting-guide.md)** - Common issues

### Component-Specific
- **[Airflow DAG Standards](.kiro/steering/airflow-dag-standards.md)** - DAG development
- **[Data Modeling Guide](.kiro/steering/data-modeling-guide.md)** - dbt patterns
- **[Testing Standards](.kiro/steering/testing-standards.md)** - Quality assurance

## Development Workflow

### Code Quality
- **Type Safety**: Python type hints required
- **Testing**: 80% minimum code coverage
- **Security**: Automated vulnerability scanning
- **Documentation**: Comprehensive docstrings and README files

### Data Quality
- **Validation**: Automated data quality checks
- **Monitoring**: SLA compliance tracking (95% success rate)
- **Freshness**: Data must be < 2 hours old
- **Lineage**: Complete data flow documentation

### Deployment Process
1. **Feature Development**: Create feature branch from main
2. **Local Testing**: Validate changes in local environment
3. **Code Review**: Peer review with security and quality checks
4. **Staging Deployment**: Test in staging environment
5. **Production Release**: Automated deployment with rollback capability

## Monitoring & Operations

### Key Metrics
- **Pipeline SLA**: 95% success rate target
- **Data Freshness**: < 2 hours latency
- **System Availability**: 99.9% uptime target
- **Data Quality Score**: > 90% quality threshold

### Alerting
- **Critical**: System down, data loss (15-minute response)
- **High**: SLA breach, major functionality impaired (1-hour response)
- **Medium**: Performance degradation (4-hour response)

### Health Checks
- Service availability monitoring
- Data pipeline execution tracking
- Resource utilization alerts
- Security event monitoring

## Security

### Data Protection
- **Encryption**: All data encrypted in transit and at rest
- **Access Control**: Role-based access with least privilege
- **Audit Logging**: Comprehensive security event tracking
- **Data Masking**: PII protection in non-production environments

### Credential Management
- **No Hardcoded Secrets**: Environment variable configuration
- **Secret Rotation**: 90-day rotation policy
- **Multi-Factor Authentication**: Required for production access

## Contributing

### Development Standards
1. Follow **[Project Standards](.kiro/steering/project-standards.md)**
2. Implement **[Security Guidelines](.kiro/steering/security-guidelines.md)**
3. Meet **[Testing Requirements](.kiro/steering/testing-standards.md)**
4. Update documentation for all changes

### Pull Request Process
1. Create feature branch from `main`
2. Implement changes with tests
3. Update relevant documentation
4. Submit PR with detailed description
5. Address review feedback
6. Merge after approval and CI/CD success

## Support

### Getting Help
1. Check **[Troubleshooting Guide](.kiro/steering/troubleshooting-guide.md)**
2. Review component-specific documentation
3. Search existing issues and discussions
4. Contact team leads for architecture questions

### Reporting Issues
- **Security Issues**: Follow responsible disclosure process
- **Bugs**: Use issue template with reproduction steps
- **Feature Requests**: Provide business justification and requirements

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Status**: Production Ready ✅  
**Last Updated**: January 2025  
**Maintainers**: Data Engineering Team