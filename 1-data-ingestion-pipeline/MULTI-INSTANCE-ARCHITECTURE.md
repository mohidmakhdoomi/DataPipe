# Multi-Instance Kafka Connect Architecture

## Overview

This implementation transforms the single Kafka Connect instance into 4 table-specific instances, each handling one table with dedicated PostgreSQL source and S3 sink connectors.

## Architecture Changes

### Before (Single Instance)
```
PostgreSQL → Single Kafka Connect (1Gi) → Kafka → S3
             ├─ All 4 tables
             ├─ Single replication slot
             └─ Shared internal topics
```

### After (Multi-Instance)
```
PostgreSQL → Users KC (250Mi)      → Kafka → S3 (table=users)
          → Products KC (250Mi)    → Kafka → S3 (table=products)
          → Orders KC (250Mi)      → Kafka → S3 (table=orders)
          → Order Items KC (250Mi) → Kafka → S3 (table=order_items)
```

## Key Benefits

### 1. **Fault Isolation**
- Failure in one table's processing doesn't affect others
- Independent restart and recovery per table
- Isolated error handling and dead letter queues

### 2. **Independent Scaling**
- Table-specific resource allocation
- Independent connector tuning
- Separate performance optimization

### 3. **Easier Troubleshooting**
- Table-specific logs and metrics
- Isolated connector status monitoring
- Clearer error attribution

### 4. **Parallel Processing**
- True parallelism across all tables
- Independent processing rates
- No shared resource contention

### 5. **Resource Efficiency**
- Same total memory usage (4 × 250Mi = 1Gi)
- Better resource utilization per table
- Optimized JVM settings per instance

## Implementation Details

### Resource Allocation
| Component | Memory | CPU | Notes |
|-----------|--------|-----|-------|
| Users KC | 250Mi | 125m/250m | Handles users table only |
| Products KC | 250Mi | 125m/250m | Handles products table only |
| Orders KC | 250Mi | 125m/250m | Handles orders table only |
| Order Items KC | 250Mi | 125m/250m | Handles order_items table only |
| **Total** | **1Gi** | **500m/1** | **Same as before** |

### PostgreSQL Changes
- **Replication Slots**: Increased from 4 to 8
- **WAL Senders**: Increased from 4 to 8
- **Publications**: Separate publication per table
- **WAL Keep Size**: Increased to 2GB (from 1GB)

### Connector Configuration
Each instance has:
- **Unique group.id**: `connect-cluster-{table}`
- **Separate internal topics**: `connect-configs-{table}`, etc.
- **Table-specific replication slot**: `debezium_slot_{table}`
- **Dedicated publication**: `dbz_publication_{table}`
- **Independent error handling**: `connect-dlq-{table}`

### Network Access
| Instance | Port | External Access |
|----------|------|----------------|
| Users | 8083 | http://localhost:8083 |
| Products | 8084 | http://localhost:8084 |
| Orders | 8085 | http://localhost:8085 |
| Order Items | 8086 | http://localhost:8086 |

## File Structure

```
1-data-ingestion-pipeline/
├── task4-postgresql-statefulset.yaml
├── kafka-connect-users-deployment.yaml
├── kafka-connect-products-deployment.yaml
├── kafka-connect-orders-deployment.yaml
├── kafka-connect-order-items-deployment.yaml
├── connectors/
│   ├── users-debezium-connector.json
│   ├── users-s3-sink-connector.json
│   ├── products-debezium-connector.json
│   ├── products-s3-sink-connector.json
│   ├── orders-debezium-connector.json
│   ├── orders-s3-sink-connector.json
│   ├── order-items-debezium-connector.json
│   └── order-items-s3-sink-connector.json
├── kind-config-multi-instance.yaml
├── 03-network-policies-multi-instance.yaml
├── deploy-multi-instance.sh
├── verify-multi-instance.sh
└── MULTI-INSTANCE-ARCHITECTURE.md
```

## Deployment Instructions

### 1. Deploy the Architecture
```bash
cd /e/Projects/DataPipe/1-data-ingestion-pipeline
./deploy-multi-instance.sh
```

### 2. Verify the Deployment
```bash
./verify-multi-instance.sh
```

### 3. Monitor the Instances
```bash
# Check all instances
kubectl get pods -n data-ingestion -l component=worker

# Check specific instance logs
kubectl logs -n data-ingestion -l app=kafka-connect-users -f

# Check connector status
curl http://localhost:8083/connectors  # Users
curl http://localhost:8084/connectors  # Products
curl http://localhost:8085/connectors  # Orders
curl http://localhost:8086/connectors  # Order Items
```

## S3 Data Organization

With the multi-instance architecture, S3 data is organized by table:

```
s3://your-bucket/
├── table=users/
│   └── year=2024/month=01/day=15/hour=10/
├── table=products/
│   └── year=2024/month=01/day=15/hour=10/
├── table=orders/
│   └── year=2024/month=01/day=15/hour=10/
└── table=order_items/
    └── year=2024/month=01/day=15/hour=10/
```

## Monitoring and Troubleshooting

### Health Checks
```bash
# Check instance health
curl http://localhost:8083/  # Users
curl http://localhost:8084/  # Products
curl http://localhost:8085/  # Orders
curl http://localhost:8086/  # Order Items

# Check connector status
curl http://localhost:8083/connectors/postgres-cdc-users-connector/status
curl http://localhost:8083/connectors/s3-sink-users-connector/status
```

### Common Issues

1. **Instance Not Starting**
   - Check resource allocation
   - Verify plugin installation
   - Check PostgreSQL connectivity

2. **Connector Failures**
   - Verify replication slot availability
   - Check publication permissions
   - Validate S3 credentials

3. **Performance Issues**
   - Monitor JVM heap usage
   - Check Kafka consumer lag
   - Verify network policies

## Migration from Single Instance

To migrate from the existing single instance:

1. **Backup Current State**
   ```bash
   kubectl get connectors -o yaml > backup-connectors.yaml
   ```

2. **Deploy Multi-Instance**
   ```bash
   ./deploy-multi-instance.sh
   ```

3. **Verify Data Flow**
   ```bash
   ./verify-multi-instance.sh
   ```

4. **Remove Old Instance** (optional)
   ```bash
   kubectl delete deployment kafka-connect -n data-ingestion
   ```

## Performance Comparison

| Metric | Single Instance | Multi-Instance | Improvement |
|--------|----------------|----------------|-------------|
| Fault Tolerance | Single Point of Failure | Isolated Failures | ✅ Better |
| Resource Usage | 1Gi shared | 4×250Mi dedicated | ✅ Same total, better isolation |
| Troubleshooting | Mixed logs | Table-specific logs | ✅ Much easier |
| Scaling | All-or-nothing | Per-table | ✅ More flexible |
| Parallel Processing | Limited | True parallelism | ✅ Better throughput |

## Conclusion

The multi-instance architecture provides superior fault isolation, easier troubleshooting, and better operational flexibility while maintaining the same resource footprint. This approach is particularly beneficial for production environments where table-specific processing requirements and fault tolerance are critical.