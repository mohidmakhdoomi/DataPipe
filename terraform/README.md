# Infrastructure Setup

This Terraform configuration creates a complete AWS infrastructure for our enterprise data pipeline.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        AWS VPC                              │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  Public Subnets │    │        Private Subnets          │ │
│  │                 │    │  ┌─────────┐  ┌─────────────┐   │ │
│  │  NAT Gateways   │    │  │   EKS   │  │     RDS     │   │ │
│  │                 │    │  │ Cluster │  │ PostgreSQL  │   │ │
│  └─────────────────┘    │  └─────────┘  └─────────────┘   │ │
│                         │  ┌─────────────────────────────┐ │ │
│                         │  │         MSK Kafka           │ │ │
│                         │  │      (3 Brokers)            │ │ │
│                         │  └─────────────────────────────┘ │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      S3 Data Lake                          │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐   │
│  │  Raw Data   │ │ Processed   │ │   Curated Data      │   │
│  │   Bucket    │ │   Bucket    │ │     Bucket          │   │
│  └─────────────┘ └─────────────┘ └─────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Components Created

### Networking
- **VPC** with public and private subnets across 3 AZs
- **Internet Gateway** for public internet access
- **NAT Gateways** for private subnet internet access
- **Route Tables** and security groups

### Compute
- **EKS Cluster** (v1.28) for running containerized workloads
- **EKS Node Group** with auto-scaling (1-10 nodes)
- **Security Groups** with proper ingress/egress rules

### Storage
- **S3 Buckets** for data lake (raw, processed, curated)
- **S3 Bucket** for Airflow logs
- **Versioning and encryption** enabled on all buckets

### Database
- **RDS PostgreSQL** for transactional data
- **Multi-AZ** deployment for high availability
- **Encrypted storage** and automated backups
- **Secrets Manager** for credential management

### Streaming
- **MSK (Managed Kafka)** cluster with 3 brokers
- **CloudWatch logging** enabled
- **Encryption** at rest and in transit
- **Custom configuration** for optimal performance

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **kubectl** for EKS cluster management

## Quick Start

1. **Copy the example variables file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit terraform.tfvars** with your desired configuration

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Plan the deployment:**
   ```bash
   terraform plan
   ```

5. **Apply the configuration:**
   ```bash
   terraform apply
   ```

## Configuration

Key variables you can customize in `terraform.tfvars`:

- `aws_region`: AWS region for deployment
- `environment`: Environment name (dev/staging/prod)
- `eks_node_instance_types`: EC2 instance types for EKS nodes
- `rds_instance_class`: RDS instance size
- `kafka_instance_type`: MSK broker instance type

## Outputs

After deployment, Terraform will output important connection details:
- EKS cluster endpoint and certificate
- RDS connection details (stored in Secrets Manager)
- MSK bootstrap brokers
- S3 bucket names

## Cost Optimization

For development/testing:
- Use `t3.micro` for RDS
- Use `t3.small` for EKS nodes
- Use `kafka.t3.small` for MSK brokers

For production:
- Scale up instance types based on workload
- Enable RDS Multi-AZ
- Increase EKS node capacity

## Security Features

- All resources deployed in private subnets
- Encryption at rest for RDS and S3
- TLS encryption for MSK
- IAM roles with least privilege access
- Security groups with minimal required access
- Secrets stored in AWS Secrets Manager

## Cleanup

To destroy all resources:
```bash
terraform destroy
```

**Warning**: This will permanently delete all data and resources!