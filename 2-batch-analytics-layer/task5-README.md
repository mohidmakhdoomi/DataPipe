# Task 5: Set up Apache Iceberg on S3 for Data Lake

## Overview

Task 5 implements Apache Iceberg as the table format for the data lake layer, providing ACID transactions, schema evolution, and time travel capabilities on top of S3 storage. This establishes the foundation for reliable batch processing with strong consistency guarantees.

## Architecture Components

### 1. Apache Iceberg Features
- **ACID Transactions**: Full ACID compliance for data lake operations
- **Schema Evolution**: Add, drop, and modify columns without data rewrites
- **Time Travel**: Query historical data using snapshots
- **Partition Evolution**: Change partitioning schemes without data migration
- **Hidden Partitioning**: Automatic partition management based on column values

### 2. S3 Integration
- **Hadoop Catalog**: File-based catalog stored in S3
- **Parquet Format**: Optimized columnar storage with Snappy compression
- **Metadata Management**: Efficient metadata operations with Gzip compression
- **File Organization**: 128MB target file sizes for optimal query performance

### 3. Table Structure
- **user_events**: Partitioned by date and hour for time-series queries
- **transactions**: Partitioned by date for efficient batch processing
- **products**: Reference table without partitioning

## Prerequisites

Before running Task 5, ensure:

1. **Tasks 1-4 completed**: Kubernetes cluster, Spark Operator, S3 access, and Snowflake connection
2. **AWS S3 Access**: Valid credentials with read/write permissions
3. **Spark Operator**: Running and operational in the batch-analytics namespace
4. **Resource Availability**: At least 6Gi RAM available for Spark jobs

## Setup Instructions

### Step 1: Run the Setup Script

Execute the automated setup script:

```bash
# Make the script executable
chmod +x task5-setup-iceberg.sh

# Run the setup
./task5-setup-iceberg.sh
```

### Step 2: Monitor Job Execution

The setup script will:
1. Deploy Iceberg catalog configuration
2. Submit a comprehensive test job
3. Monitor job execution and provide logs
4. Validate the setup completion

Monitor manually if needed:

```bash
# Check SparkApplication status
kubectl get sparkapplication iceberg-setup-job -n batch-analytics

# Follow job logs
kubectl logs -f <driver-pod-name> -n batch-analytics

# Check job completion
kubectl describe sparkapplication iceberg-setup-job -n batch-analytics
```

### Step 3: Verify S3 Structure

After successful completion, verify the Iceberg warehouse structure:

```bash
# List Iceberg warehouse contents
aws s3 ls s3://<s3_bucket>/iceberg-warehouse/ --recursive

# Check namespace structure
aws s3 ls s3://<s3_bucket>/iceberg-warehouse/ecommerce/
```

## Configuration Details

### Iceberg Catalog Configuration

```properties
# Hadoop Catalog Settings
catalog-impl=org.apache.iceberg.hadoop.HadoopCatalog
warehouse=s3://<s3_bucket>/iceberg-warehouse/

# File Format Optimization
write.format.default=parquet
write.parquet.compression-codec=snappy
write.metadata.compression-codec=gzip
write.target-file-size-bytes=134217728  # 128MB

# Transaction Settings
commit.retry.num-retries=4
commit.retry.min-wait-ms=100
commit.retry.max-wait-ms=60000

# Snapshot Management
history.expire.max-snapshot-age-ms=432000000  # 5 days
history.expire.min-snapshots-to-keep=100
```

### Table Schemas

#### User Events Table
```sql
CREATE TABLE iceberg.ecommerce.user_events (
    event_id string,
    user_id string,
    session_id string,
    event_type string,
    timestamp timestamp,
    device_type string,
    browser string,
    ip_address string,
    page_url string,
    product_id string,
    search_query string,
    transaction_id string,
    user_tier string,
    properties string,
    processing_time timestamp,
    date date,
    hour int
) USING iceberg
PARTITIONED BY (date, hour)
```

#### Transactions Table
```sql
CREATE TABLE iceberg.ecommerce.transactions (
    transaction_id string,
    user_id string,
    product_id string,
    quantity int,
    unit_price decimal(10,2),
    total_amount decimal(10,2),
    discount_amount decimal(10,2),
    tax_amount decimal(10,2),
    status string,
    payment_method string,
    user_tier string,
    created_at timestamp,
    date date
) USING iceberg
PARTITIONED BY (date)
```

## Testing Scenarios

The setup job performs comprehensive testing:

### 1. S3 Connectivity Test
- Validates AWS credentials and S3 access
- Tests read/write operations to the warehouse location
- Verifies file integrity and permissions

### 2. Iceberg Namespace Creation
- Creates the `ecommerce` namespace in the Iceberg catalog
- Validates namespace structure and accessibility

### 3. Table Creation Tests
- Creates all three tables with proper schemas
- Validates partitioning strategies
- Confirms table properties and metadata

### 4. ACID Operations Testing
- **INSERT**: Adds sample data to test tables
- **SELECT**: Queries data to verify read operations
- **UPDATE**: Modifies existing records to test update capabilities
- **DELETE**: Removes records to test delete operations

### 5. Time Travel Validation
- Creates multiple snapshots through operations
- Tests reading from previous snapshots
- Validates snapshot metadata and history

### 6. Schema Evolution Testing
- Adds new columns to existing tables
- Inserts data with the new schema
- Validates backward compatibility

## Performance Optimization

### File Organization
- **Target File Size**: 128MB for optimal query performance
- **Compression**: Snappy for Parquet data, Gzip for metadata
- **Partitioning**: Date-based partitioning for time-series queries

### Spark Configuration
```properties
# Adaptive Query Execution
spark.sql.adaptive.enabled=true
spark.sql.adaptive.coalescePartitions.enabled=true
spark.sql.adaptive.skewJoin.enabled=true

# S3 Optimization
spark.hadoop.fs.s3a.connection.maximum=200
spark.hadoop.fs.s3a.threads.max=64
spark.hadoop.fs.s3a.multipart.size=104857600
spark.hadoop.fs.s3a.fast.upload=true
```

### Resource Allocation
- **Driver**: 2Gi memory, 1 CPU core
- **Executors**: 2 instances, 2Gi memory each, 1 CPU core each
- **Total**: 6Gi memory, 4 CPU cores

## Troubleshooting

### Common Issues

1. **S3 Access Denied**
   ```bash
   # Verify AWS credentials
   kubectl get secret aws-s3-credentials -n batch-analytics -o yaml
   
   # Test S3 access manually
   aws s3 ls s3://<s3_bucket>/
   ```

2. **Spark Job Fails to Start**
   ```bash
   # Check Spark Operator logs
   kubectl logs -l app.kubernetes.io/name=spark-operator -n batch-analytics
   
   # Check driver pod events
   kubectl describe pod <driver-pod-name> -n batch-analytics
   ```

3. **Iceberg Catalog Issues**
   ```bash
   # Check warehouse path accessibility
   aws s3 ls s3://<s3_bucket>/iceberg-warehouse/
   
   # Verify Iceberg dependencies
   kubectl logs <driver-pod-name> -n batch-analytics | grep -i iceberg
   ```

4. **Memory Issues**
   ```bash
   # Check resource usage
   kubectl top pods -n batch-analytics
   
   # Check node resources
   kubectl describe nodes
   ```

### Debug Commands

```bash
# Check all resources
kubectl get all -n batch-analytics

# Check ConfigMaps
kubectl get configmaps -n batch-analytics | grep iceberg

# Check SparkApplication details
kubectl describe sparkapplication iceberg-setup-job -n batch-analytics

# Get detailed logs
kubectl logs <driver-pod-name> -n batch-analytics --previous
```

## Security Considerations

### Credential Management
- AWS credentials stored in Kubernetes secrets
- Service account-based RBAC for Spark jobs
- No credentials exposed in logs or configurations

### Data Encryption
- Server-side encryption for S3 objects
- In-transit encryption via HTTPS
- Metadata encryption with Gzip compression

### Access Control
- Least privilege principle for AWS IAM permissions
- Kubernetes RBAC for resource access
- Network policies for pod-to-pod communication

## Cost Optimization

### Storage Efficiency
- Snappy compression reduces storage costs by ~30%
- Optimal file sizes reduce metadata overhead
- Automatic compaction prevents small file proliferation

### Compute Optimization
- Adaptive query execution reduces processing time
- Partition pruning minimizes data scanning
- Efficient S3 multipart uploads

### Lifecycle Management
- Automatic snapshot expiration after 5 days
- Configurable retention policies
- Metadata cleanup procedures

## Validation and Testing

### Success Criteria

Task 5 is successful when:
- ✅ Iceberg catalog configured with S3 backend
- ✅ All three tables created with proper schemas
- ✅ ACID operations (INSERT, UPDATE, DELETE) working
- ✅ Time travel queries functional
- ✅ Schema evolution capabilities validated
- ✅ Performance optimizations applied

### Test Results Interpretation

The setup job provides detailed test results:

```
🎯 ICEBERG SETUP AND TEST SUMMARY
====================================
Spark Session Creation.............. ✅ PASSED
S3 Connectivity.................... ✅ PASSED
Iceberg Namespace Creation......... ✅ PASSED
User Events Table Creation......... ✅ PASSED
Transactions Table Creation........ ✅ PASSED
Products Table Creation............ ✅ PASSED
ACID Operations.................... ✅ PASSED
Time Travel........................ ✅ PASSED
Schema Evolution................... ✅ PASSED
Table Properties Validation........ ✅ PASSED
```

## Next Steps

After successful completion of Task 5:

1. **Verify S3 Structure**: Check that Iceberg warehouse is properly organized
2. **Test Query Performance**: Run sample queries to validate performance
3. **Proceed to Task 6**: Create Iceberg tables for e-commerce data
4. **Monitor Resource Usage**: Ensure optimal resource allocation

## Files Created

### Configuration Files
- `task5-iceberg-catalog-config.yaml` - Iceberg catalog and Spark configuration
- `task5-iceberg-setup-job.yaml` - Comprehensive setup and test job
- `task5-setup-iceberg.sh` - Automated setup script
- `task5-README.md` - This documentation file

### Generated Resources
- **ConfigMaps**: `iceberg-catalog-config`, `iceberg-setup-script`
- **SparkApplication**: `iceberg-setup-job`
- **S3 Structure**: Iceberg warehouse with namespace and table metadata

## Resource Requirements

- **Memory**: 6Gi total (2Gi driver + 4Gi executors)
- **CPU**: 4 cores total (1 driver + 2 executors)
- **Storage**: S3 for data lake (minimal local storage)
- **Network**: Outbound HTTPS access to AWS S3

## Support and Documentation

- [Apache Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [Iceberg Spark Integration](https://iceberg.apache.org/docs/latest/spark-configuration/)
- [AWS S3 Best Practices](https://docs.aws.amazon.com/s3/latest/userguide/optimizing-performance.html)
- [Spark on Kubernetes](https://spark.apache.org/docs/latest/running-on-kubernetes.html)

---

**Task 5 establishes the foundation for reliable, ACID-compliant data lake operations with Apache Iceberg on S3, enabling advanced features like time travel and schema evolution for the batch analytics layer.**