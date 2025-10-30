# Batch Analytics Layer - Design Document

## Overview

This document describes the design for a comprehensive batch analytics layer that processes data from AWS S3 using Apache Iceberg, Spark batch processing, and loads results into Snowflake for business intelligence. The system includes dbt transformations for creating business-ready data marts and ensures eventual consistency with the speed layer through Lambda reconciliation.

The architecture follows Lambda Architecture principles with focus on accuracy and completeness:
- **Data Lake Processing**: Apache Iceberg on S3 for ACID transactions and schema evolution
- **Batch Processing**: Spark batch jobs for large-scale data transformation
- **Data Warehousing**: Snowflake with 3-layer architecture (Raw, Staging, Marts)
- **Transformations**: dbt for SQL-based business logic and data modeling
- **Reconciliation**: Automated consistency validation between speed and batch layers

## Architecture

### High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "Data Lake Layer"
        S3[AWS S3<br/>Parquet Files<br/>Date Partitioned]
        ICE[Apache Iceberg<br/>ACID Transactions<br/>Schema Evolution]
    end
    
    subgraph "Batch Processing Layer"
        SPARK[Spark Batch<br/>Kubernetes Operator<br/>Large-scale ETL]
        RECON[Lambda Reconciliation<br/>UUID Conversion<br/>Consistency Validation]
    end
    
    subgraph "Data Warehouse Layer"
        SF[Snowflake<br/>3-Layer Architecture<br/>Raw → Staging → Marts]
        RAW[Raw Schema<br/>Direct Ingestion<br/>Metadata Tracking]
        STAGE[Staging Schema<br/>Data Quality<br/>Business Rules]
        MARTS[Marts Schema<br/>Business Models<br/>Clustered Tables]
    end
    
    subgraph "Transformation Layer"
        DBT[dbt Core<br/>SQL Transformations<br/>Data Quality Tests]
        DOCS[Documentation<br/>Lineage Tracking<br/>Data Catalog]
    end
    
    subgraph "Infrastructure"
        K8S[Kubernetes<br/>Docker Desktop + kind<br/>12Gi RAM]
        PV[Persistent Volumes<br/>Spark Checkpoints]
    end
    
    S3 --> ICE
    ICE --> SPARK
    SPARK --> SF
    SPARK --> RECON
    SF --> RAW
    RAW --> STAGE
    STAGE --> MARTS
    DBT --> STAGE
    DBT --> MARTS
    DBT --> DOCS
    
    K8S --> PV
```

### Data Flow Architecture

#### Batch Processing Flow
1. **Data Lake Reading**: Spark reads Parquet files from S3 using Iceberg table format
2. **Data Transformation**: Complex aggregations and business logic applied at scale
3. **Quality Validation**: Comprehensive data quality checks and business rule validation
4. **Warehouse Loading**: Processed data loaded into Snowflake Raw schema with metadata
5. **dbt Transformations**: SQL-based transformations create Staging and Marts schemas

#### Reconciliation Flow
1. **Data Extraction**: Extract comparable datasets from ClickHouse and Snowflake
2. **UUID Conversion**: Handle ClickHouse UUID to Snowflake STRING conversion
3. **Consistency Validation**: Compare user sessions, transactions, and business metrics
4. **Discrepancy Reporting**: Alert on data inconsistencies with detailed analysis
5. **Convergence Tracking**: Monitor eventual consistency convergence timing

## Components and Interfaces

### Apache Spark (Batch Processing Engine)

**Purpose**: Large-scale batch processing and ETL operations
**Configuration**:
```yaml
spark:
  driver:
    resources:
      requests: { memory: "2Gi", cpu: "1000m" }
      limits: { memory: "3Gi", cpu: "1500m" }
  executor:
    instances: 2
    resources:
      requests: { memory: "3Gi", cpu: "1500m" }
      limits: { memory: "4Gi", cpu: "2000m" }
  config:
    spark.sql.adaptive.enabled: "true"
    spark.sql.adaptive.coalescePartitions.enabled: "true"
    spark.sql.adaptive.skewJoin.enabled: "true"
    spark.serializer: "org.apache.spark.serializer.KryoSerializer"
    spark.sql.extensions: "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    spark.sql.catalog.spark_catalog: "org.apache.iceberg.spark.SparkSessionCatalog"
    spark.sql.catalog.spark_catalog.type: "hive"
    spark.sql.catalog.iceberg: "org.apache.iceberg.spark.SparkCatalog"
    spark.sql.catalog.iceberg.type: "hadoop"
    spark.sql.catalog.iceberg.warehouse: "s3://data-s3-bucket/"
```

**Batch Job Structure**:
```scala
object BatchAnalyticsApp extends App {
  val spark = SparkSession.builder()
    .appName("EcommerceBatchAnalytics")
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
    .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
    .config("spark.sql.catalog.iceberg.type", "hadoop")
    .config("spark.sql.catalog.iceberg.warehouse", "s3://data-s3-bucket/")
    .getOrCreate()
  
  import spark.implicits._
  
  // Read from Iceberg tables
  val userEvents = spark.read
    .format("iceberg")
    .load("iceberg.ecommerce.user_events")
    .filter(col("date") >= lit(args(0))) // Process specific date range
  
  val transactions = spark.read
    .format("iceberg")
    .load("iceberg.ecommerce.transactions")
    .filter(col("date") >= lit(args(0)))
  
  // Complex business logic transformations
  val userSessions = calculateUserSessions(userEvents)
  val dailyMetrics = calculateDailyMetrics(userEvents, transactions)
  val userTierAnalytics = calculateUserTierAnalytics(userEvents, transactions)
  
  // Write to Snowflake
  writeToSnowflake(userSessions, "raw.user_sessions")
  writeToSnowflake(dailyMetrics, "raw.daily_metrics")
  writeToSnowflake(userTierAnalytics, "raw.user_tier_analytics")
  
  spark.stop()
}

def calculateUserSessions(events: DataFrame): DataFrame = {
  events
    .groupBy("session_id", "user_id", "user_tier")
    .agg(
      min("timestamp").as("session_start"),
      max("timestamp").as("session_end"),
      ((max(unix_timestamp(col("timestamp"))) - min(unix_timestamp(col("timestamp")))) / 60).as("session_duration_minutes"),
      countWhen(col("event_type") === "page_view").as("page_views"),
      countWhen(col("event_type") === "product_view").as("product_views"),
      countWhen(col("event_type") === "search").as("searches"),
      countWhen(col("event_type") === "add_to_cart").as("add_to_cart_events"),
      countWhen(col("event_type") === "purchase").as("purchases"),
      sum(when(col("event_type") === "purchase", 
        coalesce(col("properties.amount").cast("double"), lit(0.0))
      ).otherwise(0.0)).as("total_spent"),
      first("device_type").as("device_type"),
      first("browser").as("browser"),
      (countWhen(col("event_type") === "purchase") > 0).as("converted_to_purchase")
    )
    .withColumn("items_purchased", col("purchases"))
    .withColumn("loaded_at", current_timestamp())
    .withColumn("batch_id", lit(java.util.UUID.randomUUID().toString))
}
```

### Apache Iceberg (Data Lake Table Format)

**Purpose**: ACID transactions and schema evolution for data lake
**Configuration**:
```yaml
iceberg:
  catalog_type: "hadoop"
  warehouse_location: "s3://data-s3-bucket/"
  file_format: "parquet"
  compression: "snappy"
  table_properties:
    write.parquet.compression-codec: "snappy"
    write.metadata.compression-codec: "gzip"
    write.target-file-size-bytes: "134217728"  # 128MB
    commit.retry.num-retries: "4"
    commit.retry.min-wait-ms: "100"
```

**Table Definitions**:
```sql
-- User events table with proper partitioning
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
TBLPROPERTIES (
    'write.target-file-size-bytes'='134217728',
    'write.parquet.compression-codec'='snappy'
);

-- Transactions table
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
TBLPROPERTIES (
    'write.target-file-size-bytes'='134217728',
    'write.parquet.compression-codec'='snappy'
);
```

### Snowflake (Data Warehouse)

**Purpose**: Comprehensive data warehouse with 3-layer architecture
**Configuration**:
```yaml
snowflake:
  account: "your-account.snowflakecomputing.com"
  warehouse: "COMPUTE_WH"
  warehouse_size: "SMALL"
  auto_suspend: 300  # 5 minutes
  auto_resume: true
  database: "ECOMMERCE_DW"
  role: "TRANSFORMER"
```

**3-Layer Schema Architecture**:

**Raw Schema - Direct Data Ingestion**:
```sql
-- Raw events table (mirrors ClickHouse structure with UUID->STRING conversion)
CREATE SCHEMA raw;

CREATE TABLE raw.user_events (
    event_id STRING,  -- Converted from ClickHouse UUID
    user_id STRING,   -- Converted from ClickHouse UUID
    session_id STRING, -- Converted from ClickHouse UUID
    event_type STRING,
    timestamp TIMESTAMP_NTZ,
    device_type STRING,
    browser STRING,
    ip_address STRING,
    
    -- Event-specific fields
    page_url STRING,
    product_id STRING,
    search_query STRING,
    transaction_id STRING, -- Converted from ClickHouse UUID
    
    -- User enrichment
    user_tier STRING,
    
    -- Properties as JSON
    properties VARIANT,
    
    -- Metadata fields
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    batch_id STRING,
    file_name STRING
)
CLUSTER BY (TO_DATE(timestamp), user_tier);

-- Raw transactions table
CREATE TABLE raw.transactions (
    transaction_id STRING,
    user_id STRING,
    product_id STRING,
    quantity NUMBER,
    unit_price NUMBER(10,2),
    total_amount NUMBER(10,2),
    discount_amount NUMBER(10,2),
    tax_amount NUMBER(10,2),
    status STRING,
    payment_method STRING,
    user_tier STRING,
    created_at TIMESTAMP_NTZ,
    
    -- Metadata
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    batch_id STRING
)
CLUSTER BY (TO_DATE(created_at), user_tier);

-- Raw user sessions from batch processing
CREATE TABLE raw.user_sessions (
    session_id STRING,
    user_id STRING,
    user_tier STRING,
    session_start TIMESTAMP_NTZ,
    session_end TIMESTAMP_NTZ,
    session_duration_minutes NUMBER,
    page_views NUMBER,
    product_views NUMBER,
    searches NUMBER,
    add_to_cart_events NUMBER,
    purchases NUMBER,
    total_spent NUMBER(10,2),
    items_purchased NUMBER,
    device_type STRING,
    browser STRING,
    converted_to_purchase BOOLEAN,
    loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    batch_id STRING
)
CLUSTER BY (TO_DATE(session_start), user_tier);
```

**Staging Schema - Data Quality and Business Rules**:
```sql
CREATE SCHEMA staging;

-- Staging events with data quality checks
CREATE TABLE staging.events_cleaned (
    event_id STRING,
    user_id STRING,
    session_id STRING,
    event_type STRING,
    timestamp TIMESTAMP_NTZ,
    device_type STRING,
    browser STRING,
    ip_address STRING,
    
    -- Event-specific fields (properly typed)
    page_url STRING,
    product_id STRING,
    search_query STRING,
    transaction_id STRING,
    user_tier STRING,
    
    -- Parsed properties
    properties_parsed VARIANT,
    
    -- Data quality flags
    is_valid BOOLEAN,
    validation_errors VARIANT,
    
    -- Business rule flags
    is_bot_traffic BOOLEAN,
    is_test_user BOOLEAN,
    
    processed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (TO_DATE(timestamp), event_type, user_tier);

-- Staging user sessions with business logic
CREATE TABLE staging.user_sessions_enhanced (
    session_id STRING,
    user_id STRING,
    user_tier STRING,
    session_start TIMESTAMP_NTZ,
    session_end TIMESTAMP_NTZ,
    session_duration_minutes NUMBER,
    
    -- Activity metrics
    page_views NUMBER,
    product_views NUMBER,
    searches NUMBER,
    add_to_cart_events NUMBER,
    purchases NUMBER,
    
    -- Business metrics
    total_spent NUMBER(10,2),
    items_purchased NUMBER,
    avg_order_value NUMBER(10,2),
    
    -- Session context
    device_type STRING,
    browser STRING,
    
    -- Conversion metrics
    converted_to_purchase BOOLEAN,
    conversion_time_minutes NUMBER,
    
    -- Business flags
    is_high_value_session BOOLEAN,
    is_bounce_session BOOLEAN,
    
    processed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (TO_DATE(session_start), user_tier);
```

**Marts Schema - Business-Ready Data Models**:
```sql
CREATE SCHEMA marts;

-- Daily business metrics with comprehensive KPIs
CREATE TABLE marts.daily_metrics (
    date DATE,
    user_tier STRING,
    
    -- Traffic metrics
    unique_users NUMBER,
    sessions NUMBER,
    page_views NUMBER,
    avg_session_duration_minutes NUMBER(5,2),
    
    -- E-commerce metrics
    product_views NUMBER,
    searches NUMBER,
    add_to_cart_events NUMBER,
    purchases NUMBER,
    revenue NUMBER(10,2),
    
    -- Conversion rates
    session_to_purchase_rate NUMBER(5,4),
    view_to_cart_rate NUMBER(5,4),
    cart_to_purchase_rate NUMBER(5,4),
    
    -- Business KPIs
    avg_order_value NUMBER(10,2),
    revenue_per_user NUMBER(10,2),
    customer_lifetime_value NUMBER(10,2),
    
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (date, user_tier);

-- User tier performance analytics
CREATE TABLE marts.user_tier_analytics (
    date DATE,
    user_tier STRING,
    
    -- User behavior metrics
    avg_events_per_session NUMBER(5,2),
    avg_products_viewed_per_session NUMBER(5,2),
    avg_searches_per_session NUMBER(5,2),
    
    -- Purchase behavior
    purchase_frequency NUMBER(5,4),
    avg_purchase_amount NUMBER(10,2),
    repeat_purchase_rate NUMBER(5,4),
    
    -- Engagement metrics
    bounce_rate NUMBER(5,4),
    time_to_purchase_minutes NUMBER(8,2),
    
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (date, user_tier);

-- Product performance analytics
CREATE TABLE marts.product_performance (
    date DATE,
    product_id STRING,
    
    -- View metrics
    views NUMBER,
    unique_viewers NUMBER,
    avg_view_duration_seconds NUMBER(8,2),
    
    -- Conversion metrics
    add_to_carts NUMBER,
    purchases NUMBER,
    view_to_cart_rate NUMBER(5,4),
    cart_to_purchase_rate NUMBER(5,4),
    
    -- Revenue metrics
    revenue NUMBER(10,2),
    avg_selling_price NUMBER(10,2),
    
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CLUSTER BY (date, product_id);
```

### dbt Core (Data Transformation)

**Purpose**: SQL-based transformations and business logic
**Project Structure**:
```
dbt_project/
├── dbt_project.yml
├── models/
│   ├── staging/
│   │   ├── _staging__sources.yml
│   │   ├── stg_events_cleaned.sql
│   │   ├── stg_user_sessions_enhanced.sql
│   │   └── stg_transactions_validated.sql
│   ├── intermediate/
│   │   ├── int_user_behavior_metrics.sql
│   │   ├── int_conversion_funnels.sql
│   │   └── int_product_analytics.sql
│   └── marts/
│       ├── mart_daily_metrics.sql
│       ├── mart_user_tier_analytics.sql
│       └── mart_product_performance.sql
├── tests/
│   ├── generic/
│   └── singular/
├── macros/
│   ├── business_logic/
│   └── data_quality/
└── docs/
```

**Example dbt Model - Daily Metrics**:
```sql
-- models/marts/mart_daily_metrics.sql
{{ config(
    materialized='incremental',
    unique_key=['date', 'user_tier'],
    cluster_by=['date', 'user_tier'],
    on_schema_change='fail'
) }}

WITH daily_sessions AS (
    SELECT 
        DATE(session_start) as date,
        user_tier,
        COUNT(DISTINCT session_id) as sessions,
        COUNT(DISTINCT user_id) as unique_users,
        SUM(page_views) as page_views,
        AVG(session_duration_minutes) as avg_session_duration_minutes,
        SUM(product_views) as product_views,
        SUM(searches) as searches,
        SUM(add_to_cart_events) as add_to_cart_events,
        SUM(purchases) as purchases,
        SUM(total_spent) as revenue,
        SUM(CASE WHEN converted_to_purchase THEN 1 ELSE 0 END) as converting_sessions
    FROM {{ ref('stg_user_sessions_enhanced') }}
    {% if is_incremental() %}
        WHERE DATE(session_start) > (SELECT MAX(date) FROM {{ this }})
    {% endif %}
    GROUP BY 1, 2
),

conversion_metrics AS (
    SELECT 
        date,
        user_tier,
        sessions,
        unique_users,
        page_views,
        avg_session_duration_minutes,
        product_views,
        searches,
        add_to_cart_events,
        purchases,
        revenue,
        
        -- Conversion rates
        CASE WHEN sessions > 0 
            THEN converting_sessions::FLOAT / sessions 
            ELSE 0 END as session_to_purchase_rate,
        CASE WHEN product_views > 0 
            THEN add_to_cart_events::FLOAT / product_views 
            ELSE 0 END as view_to_cart_rate,
        CASE WHEN add_to_cart_events > 0 
            THEN purchases::FLOAT / add_to_cart_events 
            ELSE 0 END as cart_to_purchase_rate,
        
        -- Business KPIs
        CASE WHEN purchases > 0 
            THEN revenue / purchases 
            ELSE 0 END as avg_order_value,
        CASE WHEN unique_users > 0 
            THEN revenue / unique_users 
            ELSE 0 END as revenue_per_user
    FROM daily_sessions
)

SELECT 
    *,
    {{ calculate_customer_lifetime_value('user_tier', 'revenue_per_user') }} as customer_lifetime_value,
    CURRENT_TIMESTAMP() as created_at
FROM conversion_metrics
```

**dbt Tests**:
```sql
-- tests/singular/test_daily_metrics_completeness.sql
SELECT 
    date,
    user_tier,
    COUNT(*) as record_count
FROM {{ ref('mart_daily_metrics') }}
WHERE date >= CURRENT_DATE - 7
GROUP BY 1, 2
HAVING record_count != 1  -- Should have exactly one record per date/tier combination
```

### Lambda Reconciliation

**Purpose**: Ensure eventual consistency between speed and batch layers
**Implementation**:
```scala
object LambdaReconciliation extends App {
  
  case class ReconciliationResult(
    date: String,
    metric: String,
    speedLayerValue: Double,
    batchLayerValue: Double,
    difference: Double,
    percentageDifference: Double,
    withinTolerance: Boolean
  )
  
  def reconcileUserSessions(date: String): Seq[ReconciliationResult] = {
    // Extract from ClickHouse (speed layer)
    val speedLayerData = extractFromClickHouse(s"""
      SELECT 
        user_tier,
        COUNT(DISTINCT session_id) as sessions,
        SUM(page_views) as page_views,
        SUM(purchases) as purchases,
        SUM(total_spent) as revenue
      FROM user_sessions_realtime 
      WHERE toDate(session_start) = '$date'
      GROUP BY user_tier
    """)
    
    // Extract from Snowflake (batch layer)
    val batchLayerData = extractFromSnowflake(s"""
      SELECT 
        user_tier,
        SUM(sessions) as sessions,
        SUM(page_views) as page_views,
        SUM(purchases) as purchases,
        SUM(revenue) as revenue
      FROM marts.daily_metrics 
      WHERE date = '$date'
      GROUP BY user_tier
    """)
    
    // Compare and generate reconciliation results
    val tolerance = 0.05 // 5% tolerance
    
    for {
      speedRow <- speedLayerData
      batchRow <- batchLayerData
      if speedRow.getString("user_tier") == batchRow.getString("user_tier")
      metric <- Seq("sessions", "page_views", "purchases", "revenue")
    } yield {
      val speedValue = speedRow.getDouble(metric)
      val batchValue = batchRow.getDouble(metric)
      val difference = Math.abs(speedValue - batchValue)
      val percentageDifference = if (batchValue != 0) difference / batchValue else 0.0
      
      ReconciliationResult(
        date = date,
        metric = s"${speedRow.getString("user_tier")}_$metric",
        speedLayerValue = speedValue,
        batchLayerValue = batchValue,
        difference = difference,
        percentageDifference = percentageDifference,
        withinTolerance = percentageDifference <= tolerance
      )
    }
  }
  
  def handleUUIDConversion(clickhouseUUID: String): String = {
    // Convert ClickHouse UUID format to Snowflake STRING format
    clickhouseUUID.toLowerCase()
  }
}
```

## Error Handling

### Data Quality Validation

**dbt Data Quality Tests**:
```sql
-- macros/data_quality/test_business_rules.sql
{% macro test_business_rules() %}
    -- Test that user tier transitions are valid
    SELECT *
    FROM {{ ref('stg_user_sessions_enhanced') }}
    WHERE user_tier NOT IN ('bronze', 'silver', 'gold', 'platinum', 'unknown')
    
    UNION ALL
    
    -- Test that session duration is reasonable
    SELECT *
    FROM {{ ref('stg_user_sessions_enhanced') }}
    WHERE session_duration_minutes < 0 OR session_duration_minutes > 1440  -- Max 24 hours
    
    UNION ALL
    
    -- Test that purchase amounts are positive
    SELECT *
    FROM {{ ref('stg_user_sessions_enhanced') }}
    WHERE total_spent < 0
{% endmacro %}
```

### Monitoring and Alerting

**Key Metrics**:
```yaml
metrics:
  - name: "spark_batch_job_duration"
    type: "histogram"
    labels: ["job_name", "date"]
  - name: "snowflake_load_success_rate"
    type: "gauge"
    labels: ["schema", "table"]
  - name: "dbt_model_execution_time"
    type: "histogram"
    labels: ["model_name", "materialization"]
  - name: "lambda_reconciliation_discrepancy"
    type: "gauge"
    labels: ["metric", "user_tier"]
```

**Alert Rules**:
```yaml
alerts:
  - name: "BatchJobFailure"
    condition: "spark_batch_job_duration == 0"
    severity: "critical"
    duration: "1m"
  - name: "HighReconciliationDiscrepancy"
    condition: "lambda_reconciliation_discrepancy > 0.1"
    severity: "warning"
    duration: "5m"
  - name: "dbtModelFailure"
    condition: "rate(dbt_model_failures[10m]) > 0"
    severity: "critical"
    duration: "1m"
```

## Performance and Scalability

### Resource Allocation (12Gi Total)
```yaml
resource_allocation:
  spark_driver: 3Gi RAM, 1.5 CPU
  spark_executors: 8Gi RAM (4Gi each), 4 CPU
  dbt_runner: 1Gi RAM, 0.5 CPU
  total: 12Gi RAM, 6 CPU
```

### Performance Optimization

**Spark Batch Tuning**:
```properties
# Large dataset optimization
spark.sql.adaptive.enabled=true
spark.sql.adaptive.coalescePartitions.enabled=true
spark.sql.adaptive.skewJoin.enabled=true
spark.sql.adaptive.localShuffleReader.enabled=true

# Memory optimization
spark.executor.memory=4g
spark.executor.memoryFraction=0.8
spark.executor.cores=2
spark.sql.shuffle.partitions=200
```

**Snowflake Optimization**:
```sql
-- Optimize clustering for query performance
ALTER TABLE marts.daily_metrics 
CLUSTER BY (date, user_tier);

-- Optimize warehouse for batch loads
ALTER WAREHOUSE COMPUTE_WH SET 
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
```

This design provides a comprehensive batch analytics layer that ensures data accuracy, supports complex business intelligence requirements, and maintains eventual consistency with the speed layer through automated reconciliation processes.