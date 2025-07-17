# Dimensional Model Design

## Star Schema Components

### 1. Fact Tables (Measures/Metrics)
**fact_transactions** - Central fact table containing business events
- **Grain**: One row per transaction
- **Measures**: 
  - total_amount (additive)
  - quantity (additive)
  - recognized_revenue (additive)
  - discount_amount (additive)
  - tax_amount (additive)
- **Foreign Keys**: user_id, product_id, transaction_date
- **Degenerate Dimensions**: transaction_id, payment_method, status

### 2. Dimension Tables (Context/Attributes)

#### dim_users (Customer Dimension)
- **Type**: Slowly Changing Dimension (SCD Type 1)
- **Grain**: One row per unique customer
- **Attributes**:
  - Demographics: age, age_group, country, city
  - Behavioral: customer_segment, engagement_score
  - RFM Analysis: recency_score, frequency_score, monetary_score
  - Calculated: annual_clv_estimate, churn_risk_flag

#### dim_products (Product Dimension)  
- **Type**: Slowly Changing Dimension (SCD Type 1)
- **Grain**: One row per unique product
- **Attributes**:
  - Descriptive: product_name, description, brand
  - Categorical: category, subcategory, category_group
  - Financial: price, cost, margin_percentage
  - Performance: price_tier, performance_tier

#### dim_time (Time Dimension) - Implicit
- **Type**: Static dimension
- **Grain**: One row per day
- **Attributes**:
  - Calendar: year, month, quarter, day_of_week
  - Business: day_type (weekend/weekday), time_of_day
  - Fiscal: fiscal_year, fiscal_quarter (if different from calendar)

## Benefits of This Dimensional Model

### 1. Query Performance
- **Star schema** optimizes for analytical queries
- **Denormalized dimensions** reduce joins
- **Pre-aggregated metrics** in fact table
- **Columnar storage** friendly structure

### 2. Business User Friendly
- **Intuitive structure** mirrors business processes
- **Self-documenting** with clear dimension attributes
- **Consistent grain** across all fact tables
- **Business terminology** in column names

### 3. Scalability
- **Additive measures** support aggregation at any level
- **Conformed dimensions** enable cross-process analysis
- **Incremental loading** patterns supported
- **Partitioning** by date dimension

## Analytical Capabilities

### Customer Analysis
```sql
-- Customer segmentation analysis
SELECT 
    customer_segment,
    COUNT(*) as customers,
    AVG(annual_clv_estimate) as avg_clv,
    SUM(total_revenue) as segment_revenue
FROM dim_users
GROUP BY customer_segment;
```

### Product Performance
```sql
-- Product category performance
SELECT 
    p.category,
    SUM(f.recognized_revenue) as revenue,
    COUNT(DISTINCT f.user_id) as customers,
    AVG(f.total_amount) as avg_order_value
FROM fact_transactions f
JOIN dim_products p ON f.product_id = p.product_id
WHERE f.is_successful = true
GROUP BY p.category;
```

### Time-based Analysis
```sql
-- Monthly revenue trend
SELECT 
    DATE_TRUNC('month', transaction_date) as month,
    SUM(recognized_revenue) as monthly_revenue,
    COUNT(DISTINCT user_id) as active_customers
FROM fact_transactions
WHERE is_successful = true
GROUP BY month
ORDER BY month;
```

## Advanced Dimensional Concepts Used

### 1. Slowly Changing Dimensions (SCD)
- **Type 1 (Overwrite)**: Used for dim_users and dim_products
- **Type 2 (Historical)**: Could be implemented for price changes
- **Type 3 (Previous Value)**: Could track previous customer segment

### 2. Degenerate Dimensions
- **transaction_id**: Stored in fact table (no separate dimension)
- **payment_method**: Low cardinality, stored in fact
- **status**: Transaction-specific, stored in fact

### 3. Junk Dimensions (Potential)
- Could create dim_transaction_flags for:
  - has_discount (Y/N)
  - is_weekend (Y/N)
  - is_high_value (Y/N)
  - multi_item_purchase (Y/N)

### 4. Role-Playing Dimensions
- **Date dimension** could play multiple roles:
  - Transaction Date
  - Registration Date
  - Last Login Date

## Conformed Dimensions

### dim_users
- Used across multiple fact tables
- Consistent customer attributes
- Single source of truth for customer data

### dim_products  
- Shared across transaction and event facts
- Consistent product hierarchy
- Single source of truth for product data

### dim_time
- Universal time dimension
- Consistent calendar attributes
- Supports all time-based analysis

## Data Warehouse Layers

### 1. Staging Layer (ODS - Operational Data Store)
- **Purpose**: Data cleansing and standardization
- **Models**: stg_users, stg_products, stg_transactions, stg_user_events
- **Characteristics**: 1:1 with source systems, minimal transformation

### 2. Intermediate Layer (Data Marts)
- **Purpose**: Business logic and aggregations
- **Models**: int_user_metrics, int_product_performance
- **Characteristics**: Reusable business rules, optimized for specific domains

### 3. Presentation Layer (Star Schema)
- **Purpose**: Analytics and reporting
- **Models**: dim_users, dim_products, fact_transactions
- **Characteristics**: Denormalized, business-friendly, optimized for queries