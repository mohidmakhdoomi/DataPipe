# Task 3: AWS S3 Access Configuration

This task configures AWS S3 access for the batch analytics layer, enabling Iceberg data lake operations with proper security, lifecycle management, and cost optimization.

## Overview

Task 3 implements the following components:
- AWS credentials management using Kubernetes secrets
- S3 bucket configuration with lifecycle policies
- Server-side encryption for data at rest
- Connectivity testing and validation
- Spark + S3 + Iceberg integration testing

## Prerequisites

Before running this task, ensure:
1. Tasks 1 and 2 are completed (Kind cluster and Spark Operator deployed)
2. You have AWS credentials with S3 access permissions
3. An S3 bucket exists or you have permissions to create one
4. AWS CLI is installed (optional but recommended)

## Required AWS Permissions

Your AWS credentials need the following permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::your-bucket-name",
                "arn:aws:s3:::your-bucket-name/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutBucketLifecycleConfiguration",
                "s3:PutBucketEncryption",
                "s3:GetBucketLifecycleConfiguration",
                "s3:GetBucketEncryption"
            ],
            "Resource": "arn:aws:s3:::your-bucket-name"
        }
    ]
}
```

## Setup Instructions

### 1. Set Environment Variables

```bash
export AWS_ACCESS_KEY_ID="your-access-key-id"
export AWS_SECRET_ACCESS_KEY="your-secret-access-key"
export AWS_DEFAULT_REGION="us-east-1"
export AWS_S3_BUCKET="data-lake-warehouse"
```

### 2. Run the Setup Script

```bash
# Make the script executable
chmod +x task3-setup-s3-access.sh

# Run the setup
./task3-setup-s3-access.sh
```

### 3. Manual Setup (Alternative)

If you prefer manual setup:

```bash
# Ensure service accounts are applied (should be done in Task 2)
kubectl apply -f batch-02-service-accounts.yaml

# Apply AWS credentials and configuration
kubectl apply -f task3-aws-s3-secrets.yaml

# Update with your actual credentials
kubectl create secret generic aws-s3-credentials \
    --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    --from-literal=AWS_DEFAULT_REGION="$AWS_DEFAULT_REGION" \
    --from-literal=AWS_S3_BUCKET="$AWS_S3_BUCKET" \
    --from-literal=AWS_S3_ENDPOINT="https://s3.amazonaws.com" \
    --from-literal=ICEBERG_WAREHOUSE_PATH="s3://$AWS_S3_BUCKET/" \
    --from-literal=ICEBERG_CATALOG_TYPE="hadoop" \
    --namespace=batch-analytics \
    --dry-run=client -o yaml | kubectl apply -f -

# Run connectivity test
kubectl apply -f task3-s3-connectivity-test.yaml

# Check test results
kubectl logs job/s3-connectivity-test -n batch-analytics
```

## Testing and Validation

### 1. S3 Connectivity Test

The connectivity test validates:
- AWS CLI configuration
- S3 bucket access permissions
- Read/write operations
- File integrity verification

```bash
# Monitor the test
kubectl logs -f job/s3-connectivity-test -n batch-analytics

# Check test completion
kubectl get job s3-connectivity-test -n batch-analytics
```

### 2. Spark S3 Iceberg Integration Test

This comprehensive test validates:
- Spark's ability to connect to S3
- Iceberg table creation and operations
- Partitioning and metadata management
- Time travel capabilities

```bash
# Run the Spark integration test
kubectl apply -f task3-spark-s3-iceberg-test.yaml

# Monitor the Spark job
kubectl logs -f sparkapplication/spark-s3-iceberg-test -n batch-analytics

# Check Spark UI (if port-forwarded)
# kubectl port-forward svc/spark-s3-iceberg-test-ui-svc 4040:4040 -n batch-analytics
```

## Configuration Details

### S3 Configuration

The setup includes optimized S3 settings:

```properties
# Connection optimization
fs.s3a.connection.maximum=200
fs.s3a.threads.max=64
fs.s3a.connection.establish.timeout=5000
fs.s3a.connection.timeout=200000

# Multipart upload optimization
fs.s3a.multipart.size=104857600          # 100MB
fs.s3a.multipart.threshold=134217728     # 128MB
fs.s3a.fast.upload=true
fs.s3a.fast.upload.buffer=disk
fs.s3a.fast.upload.active.blocks=8

# Server-side encryption
fs.s3a.server-side-encryption-algorithm=AES256
```

### Iceberg Configuration

Iceberg is configured for optimal performance:

```properties
# File format and compression
write.format.default=parquet
write.parquet.compression-codec=snappy
write.metadata.compression-codec=gzip
write.target-file-size-bytes=134217728   # 128MB

# Retry configuration
commit.retry.num-retries=4
commit.retry.min-wait-ms=100
commit.retry.max-wait-ms=60000

# Snapshot management
history.expire.max-snapshot-age-ms=432000000  # 5 days
history.expire.min-snapshots-to-keep=100
```

### Lifecycle Policies

The S3 lifecycle policy includes:

1. **Data Lake Optimization**: 
   - Standard → Standard-IA (30 days)
   - Standard-IA → Glacier (90 days)
   - Glacier → Deep Archive (365 days)

2. **Test Data Cleanup**: 
   - Automatic deletion after 7 days

3. **Spark Checkpoints**: 
   - Cleanup after 30 days

4. **Metadata Optimization**: 
   - Faster transition for metadata files

## Troubleshooting

### Common Issues

1. **Credentials Not Working**
   ```bash
   # Verify credentials are set
   kubectl get secret aws-s3-credentials -n batch-analytics -o yaml
   
   # Test AWS CLI access
   aws sts get-caller-identity
   ```

2. **S3 Bucket Access Denied**
   ```bash
   # Check bucket permissions
   aws s3 ls s3://your-bucket-name/
   
   # Verify bucket policy and IAM permissions
   ```

3. **Spark Job Fails to Start**
   ```bash
   # Check Spark Operator logs
   kubectl logs -l app.kubernetes.io/name=spark-operator -n batch-analytics
   
   # Check driver pod logs
   kubectl logs spark-s3-iceberg-test-driver -n batch-analytics
   ```

4. **Iceberg Table Creation Fails**
   ```bash
   # Check S3 permissions for warehouse path
   aws s3 ls s3://your-bucket-name/iceberg/
   
   # Verify Iceberg dependencies are loaded
   kubectl describe sparkapplication spark-s3-iceberg-test -n batch-analytics
   ```

### Debug Commands

```bash
# Check all resources
kubectl get all -n batch-analytics

# Check secrets
kubectl get secrets -n batch-analytics

# Check configmaps
kubectl get configmaps -n batch-analytics

# Check job status
kubectl describe job s3-connectivity-test -n batch-analytics

# Check Spark application status
kubectl describe sparkapplication spark-s3-iceberg-test -n batch-analytics
```

## Security Considerations

1. **Credentials Management**: 
   - AWS credentials are stored in Kubernetes secrets
   - Secrets are not exposed in logs or configurations
   - Service accounts have minimal required permissions

2. **Encryption**: 
   - Server-side encryption enabled for all S3 objects
   - In-transit encryption via HTTPS
   - Kubernetes secrets are encrypted at rest

3. **Access Control**: 
   - RBAC configured for service accounts
   - Least privilege principle applied
   - Network policies can be added for additional security

## Cost Optimization

1. **Lifecycle Policies**: 
   - Automatic transition to cheaper storage classes
   - Cleanup of temporary and test data
   - Abort incomplete multipart uploads

2. **Compression**: 
   - Snappy compression for Parquet files
   - Gzip compression for metadata

3. **File Sizing**: 
   - Optimal file sizes (128MB) for query performance
   - Reduced metadata overhead

## Next Steps

After completing Task 3:

1. Verify all tests pass successfully
2. Check S3 bucket has proper structure and permissions
3. Proceed to Task 4: Set up Snowflake connection
4. Monitor S3 costs and adjust lifecycle policies as needed

## Files Created

- `task3-aws-s3-secrets.yaml`: AWS credentials and S3 configuration
- `task3-s3-connectivity-test.yaml`: Basic S3 connectivity test job
- `task3-spark-s3-iceberg-test.yaml`: Comprehensive Spark+S3+Iceberg test
- `task3-s3-lifecycle-policy.json`: S3 lifecycle policy for cost optimization
- `task3-setup-s3-access.sh`: Automated setup script
- `task3-README.md`: This documentation file

## Files Modified

- `batch-02-service-accounts.yaml`: Added S3 access service account and RBAC

## Success Criteria

Task 3 is complete when:
- [ ] AWS credentials are properly configured in Kubernetes
- [ ] S3 connectivity test passes successfully
- [ ] Spark can read/write to S3 using Iceberg format
- [ ] Lifecycle policies are applied for cost optimization
- [ ] Server-side encryption is enabled
- [ ] All test resources can be cleaned up properly

The batch analytics layer now has secure, optimized access to AWS S3 for data lake operations.