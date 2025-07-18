# Environment Files Guide

This document provides an overview of all `.env.example` files in the project and their specific purposes.

## Overview of .env.example Files

### 1. `docker/.env.example` - Main Docker Compose Configuration
**Purpose**: Primary environment file for Docker Compose deployment
**Location**: `docker/.env.example`
**Usage**: Copy to `docker/.env` for local development

**Key Variables**:
- Database credentials (PostgreSQL, ClickHouse)
- Airflow security keys (Fernet, Secret)
- Data generation settings
- Kafka configuration
- Optional: Email, AWS, Snowflake settings

### 2. `docker/airflow/.env.example` - Kubernetes/Production Airflow
**Purpose**: Airflow configuration for Kubernetes deployments
**Location**: `docker/airflow/.env.example`
**Usage**: For containerized Airflow in Kubernetes

**Key Variables**:
- Airflow security keys and UI credentials
- Kubernetes service names for databases
- Production-scale data generation settings
- AWS and Snowflake configuration

### 3. `airflow/.env.example` - Local Airflow Development
**Purpose**: Airflow configuration for local development
**Location**: `airflow/.env.example`
**Usage**: For running Airflow locally during development

**Key Variables**:
- Local service hostnames (postgres, clickhouse)
- Development-scale settings
- All security credentials

### 4. `data-generators/.env.example` - Data Generation Service
**Purpose**: Configuration for the data generation service
**Location**: `data-generators/.env.example`
**Usage**: For running data generators independently

**Key Variables**:
- Database connection settings
- Kafka configuration
- Data generation parameters (users, products, events)

## Security Requirements

### Required Secure Variables (Must be set)
```bash
# Database Passwords
POSTGRES_PASSWORD=your_secure_postgres_password_here
CLICKHOUSE_PASSWORD=your_secure_clickhouse_password_here

# Airflow Security
AIRFLOW_FERNET_KEY=your_32_character_fernet_key_here_
AIRFLOW_SECRET_KEY=your_secret_key_here
_AIRFLOW_WWW_USER_PASSWORD=your_secure_admin_password_here
```

### Optional Secure Variables
```bash
# Snowflake (Production)
SNOWFLAKE_PASSWORD=your_secure_snowflake_password_here

# AWS (Production)
AWS_SECRET_ACCESS_KEY=your_aws_secret_access_key_here

# Email (Optional)
MAIL_PASSWORD=your_email_password
```

## Environment-Specific Differences

### Local Development (`docker/.env.example`)
- Uses `kafka:29092` for internal Docker networking
- Smaller data generation settings (1000 users, 500 products)
- Includes all optional configurations as comments

### Kubernetes Production (`docker/airflow/.env.example`)
- Uses Kubernetes service names (`.svc.cluster.local`)
- Larger data generation settings (10000 users, 1000 products)
- Production environment flag

### Local Airflow (`airflow/.env.example`)
- Uses local service names (`postgres`, `clickhouse`)
- Development environment flag
- Medium-scale data settings

### Data Generators (`data-generators/.env.example`)
- Focuses only on data generation requirements
- Uses `localhost` for local development
- Includes Kafka settings for event streaming

## Setup Instructions by Environment

### 1. Local Docker Development
```bash
cp docker/.env.example docker/.env
# Edit docker/.env with secure passwords
docker-compose up -d
```

### 2. Kubernetes Deployment
```bash
cp docker/airflow/.env.example docker/airflow/.env
# Edit with production values and Kubernetes service names
# Also update k8s/secrets/ files with base64 encoded values
```

### 3. Local Airflow Development
```bash
cp airflow/.env.example airflow/.env
# Edit with local development settings
```

### 4. Standalone Data Generation
```bash
cp data-generators/.env.example data-generators/.env
# Edit with database connection details
```

## Validation Checklist

### ✅ All Files Updated
- [x] `docker/.env.example` - Complete with all required variables
- [x] `docker/airflow/.env.example` - Kubernetes-ready configuration
- [x] `airflow/.env.example` - Local development configuration
- [x] `data-generators/.env.example` - Data generation service

### ✅ Security Compliance
- [x] No hardcoded passwords in any .env.example file
- [x] All sensitive values use placeholder text
- [x] Required variables clearly marked
- [x] Optional variables properly commented

### ✅ Consistency
- [x] Variable names consistent across files
- [x] Service names appropriate for each environment
- [x] Data generation settings scaled appropriately
- [x] All security keys included where needed

## Missing Variables Check

Based on code analysis, all required environment variables are included:

### Database Variables ✅
- POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
- CLICKHOUSE_HOST, CLICKHOUSE_PORT, CLICKHOUSE_DB, CLICKHOUSE_USER, CLICKHOUSE_PASSWORD

### Airflow Variables ✅
- AIRFLOW_FERNET_KEY, AIRFLOW_SECRET_KEY
- _AIRFLOW_WWW_USER_USERNAME, _AIRFLOW_WWW_USER_PASSWORD
- AIRFLOW_UID, AIRFLOW_PROJ_DIR, AIRFLOW_ENV

### Data Generation Variables ✅
- NUM_USERS, NUM_PRODUCTS, DAYS_OF_DATA, EVENTS_PER_DAY

### Kafka Variables ✅
- KAFKA_BOOTSTRAP_SERVERS, KAFKA_TOPIC_EVENTS, KAFKA_TOPIC_TRANSACTIONS

### Optional Production Variables ✅
- SNOWFLAKE_* (account, user, password, role, database, warehouse)
- AWS_* (access key, secret key, region)
- MAIL_* (server, username, password, sender)

## Conclusion

All `.env.example` files are now complete, secure, and consistent. No hardcoded passwords remain, and all necessary environment variables are documented with appropriate placeholder values.