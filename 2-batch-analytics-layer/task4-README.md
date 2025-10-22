# Task 4: Snowflake Connection and Authentication Setup

## Overview

This task sets up Snowflake connection and authentication for the batch analytics layer. It configures the 3-layer data warehouse architecture (Raw, Staging, Marts) and establishes connectivity between Spark and Snowflake for data processing operations.

## Architecture Components

### 1. Snowflake 3-Layer Architecture
- **Raw Schema**: Direct data ingestion from Spark batch jobs
- **Staging Schema**: Data quality checks and business rule validation
- **Marts Schema**: Business-ready data models for analytics

### 2. Connection Configuration
- Snowflake credentials management via Kubernetes secrets
- Spark-Snowflake connector configuration
- Connection pooling and performance optimization
- Auto-suspend warehouse configuration for cost optimization

### 3. Security and Authentication
- Role-based access control (TRANSFORMER role)
- Dedicated user for batch analytics operations
- Secure credential storage in Kubernetes secrets
- SSL/TLS encryption for all connections

## Files Created

### Configuration Files
- `task4-snowflake-secrets.yaml.example` - Template for Snowflake credentials
- `task4-snowflake-secrets.yaml` - Actual secrets (with placeholder values)
- `task4-snowflake-test-job.yaml` - Comprehensive test job with Python script

### Scripts
- `task4-setup-snowflake.sh` - Main setup script for Task 4
- `task4-README.md` - This documentation file

## Prerequisites

Before running Task 4, ensure:

1. **Task 1 completed**: Kubernetes cluster and namespace created
2. **Task 2 completed**: Spark Operator deployed and operational
3. **Snowflake Account**: Access to a Snowflake account with appropriate permissions
4. **Credentials**: Snowflake username, password, and account information

## Setup Instructions

### Step 1: Configure Snowflake Credentials

1. **Copy the example file**:
   ```bash
   cp task4-snowflake-secrets.yaml.example task4-snowflake-secrets.yaml
   ```

2. **Edit the credentials** in `task4-snowflake-secrets.yaml`:
   ```yaml
   stringData:
     SNOWFLAKE_ACCOUNT: "your-account.snowflakecomputing.com"
     SNOWFLAKE_USER: "BATCH_ANALYTICS_USER"
     SNOWFLAKE_PASSWORD: "your_secure_password"
     SNOWFLAKE_ROLE: "TRANSFORMER"
     SNOWFLAKE_WAREHOUSE: "COMPUTE_WH"
     SNOWFLAKE_DATABASE: "ECOMMERCE_DW"
     SNOWFLAKE_SCHEMA: "RAW"
   ```

### Step 2: Run the Setup Script

Execute the main setup script:

```bash
./task4-setup-snowflake.sh
```

This script will:
- Deploy Snowflake secrets and configuration
- Create ConfigMaps for connection properties
- Deploy test resources
- Validate the configuration
- Submit a connectivity test job

### Step 3: Verify the Setup

1. **Check deployed resources**:
   ```bash
   kubectl get secrets,configmaps -n batch-analytics | grep snowflake
   ```

2. **Monitor the connectivity test**:
   ```bash
   kubectl get sparkapplication snowflake-test-job -n batch-analytics
   kubectl logs -f sparkapplication/snowflake-test-job -n batch-analytics
   ```

3. **Verify Snowflake connection**:
   The test job will perform comprehensive connectivity tests including:
   - Basic connection validation
   - Database and schema structure verification
   - Table creation and data insertion
   - Data retrieval and aggregation
   - Cleanup operations

## Snowflake Setup Requirements

### Database and Schema Creation

Run these SQL commands in your Snowflake account:

```sql
-- Create database and schemas
CREATE DATABASE IF NOT EXISTS ECOMMERCE_DW;
USE DATABASE ECOMMERCE_DW;

CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS MARTS;

-- Create warehouse with auto-suspend
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
WITH WAREHOUSE_SIZE = 'SMALL'
AUTO_SUSPEND = 300
AUTO_RESUME = TRUE
INITIALLY_SUSPENDED = TRUE;

-- Create role and user
CREATE ROLE IF NOT EXISTS TRANSFORMER;
CREATE USER IF NOT EXISTS BATCH_ANALYTICS_USER
PASSWORD = 'your_secure_password'
DEFAULT_ROLE = 'TRANSFORMER'
DEFAULT_WAREHOUSE = 'COMPUTE_WH'
DEFAULT_NAMESPACE = 'ECOMMERCE_DW.RAW';

-- Grant permissions
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE TRANSFORMER;
GRANT USAGE ON DATABASE ECOMMERCE_DW TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA ECOMMERCE_DW.RAW TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA ECOMMERCE_DW.STAGING TO ROLE TRANSFORMER;
GRANT ALL ON SCHEMA ECOMMERCE_DW.MARTS TO ROLE TRANSFORMER;
GRANT ROLE TRANSFORMER TO USER BATCH_ANALYTICS_USER;
```

## Configuration Details

### Spark-Snowflake Connector

The configuration includes optimized settings for:

- **Performance**: Adaptive query execution, partition coalescing
- **Connectivity**: Connection pooling, timeout settings, retry logic
- **Data Handling**: Column case handling, autopushdown optimization
- **Security**: SSL encryption, credential management

### Resource Allocation

- **Driver**: 2Gi memory, 1 CPU core
- **Executor**: 2Gi memory, 1 CPU core
- **Test Duration**: ~5-10 minutes for comprehensive testing

## Troubleshooting

### Common Issues

1. **Connection Timeout**:
   - Verify Snowflake account URL format
   - Check network connectivity from Kubernetes cluster
   - Validate firewall rules

2. **Authentication Failed**:
   - Verify username and password
   - Check role permissions
   - Ensure user has access to specified warehouse and database

3. **Permission Denied**:
   - Verify role has necessary permissions
   - Check database and schema access rights
   - Validate warehouse usage permissions

### Debug Commands

```bash
# Check secret contents (base64 encoded)
kubectl get secret snowflake-credentials -n batch-analytics -o yaml

# View configuration details
kubectl get configmap snowflake-config -n batch-analytics -o yaml

# Check Spark application status
kubectl describe sparkapplication snowflake-test-job -n batch-analytics

# View detailed logs
kubectl logs -f sparkapplication/snowflake-test-job -n batch-analytics
```

## Testing Scenarios

The connectivity test performs:

1. **Basic Connection Test**: Validates account, user, role, warehouse access
2. **Schema Validation**: Checks database and schema structure
3. **Warehouse Configuration**: Verifies warehouse settings and permissions
4. **Table Operations**: Creates, inserts, and queries test data
5. **Aggregation Queries**: Tests complex SQL operations
6. **Cleanup Operations**: Removes test artifacts

## Performance Optimization

### Warehouse Configuration
- **Size**: SMALL (sufficient for development and testing)
- **Auto-suspend**: 5 minutes to minimize costs
- **Auto-resume**: Enabled for seamless operations

### Connection Settings
- **Pool Size**: 10 maximum connections
- **Timeout**: 60 seconds connection timeout
- **Retries**: 3 maximum retries with exponential backoff

## Security Considerations

1. **Credential Storage**: All credentials stored in Kubernetes secrets
2. **Encryption**: SSL/TLS encryption for all connections
3. **Access Control**: Role-based permissions with minimal required access
4. **Network Security**: Connections through secure channels only

## Cost Optimization

1. **Auto-suspend**: Warehouse automatically suspends after 5 minutes
2. **Right-sizing**: SMALL warehouse for development workloads
3. **Query Optimization**: Autopushdown and adaptive query execution
4. **Connection Pooling**: Efficient connection reuse

## Next Steps

After successful completion of Task 4:

1. **Verify connectivity test passes**
2. **Update credentials with production values** (if needed)
3. **Proceed to Task 5**: Set up Apache Iceberg on S3 for data lake
4. **Monitor resource usage** and adjust warehouse size if needed

## Resource Requirements

- **Memory**: 4Gi total (2Gi driver + 2Gi executor)
- **CPU**: 2 cores total (1 driver + 1 executor)
- **Network**: Outbound HTTPS access to Snowflake
- **Storage**: Minimal (configuration only)

## Success Criteria

Task 4 is considered successful when:

- ✅ Snowflake credentials secret created and validated
- ✅ Connection configuration deployed successfully
- ✅ Connectivity test job completes without errors
- ✅ All test scenarios pass (connection, schema, table operations)
- ✅ 3-layer architecture schemas accessible
- ✅ Spark-Snowflake connector operational

## Support and Documentation

- [Snowflake Spark Connector Documentation](https://docs.snowflake.com/en/user-guide/spark-connector)
- [Spark Operator Documentation](https://github.com/GoogleCloudPlatform/spark-on-k8s-operator)
- [Kubernetes Secrets Documentation](https://kubernetes.io/docs/concepts/configuration/secret/)