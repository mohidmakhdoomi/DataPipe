---
inclusion: fileMatch
fileMatchPattern: 'dbt/**/*.sql'
---

# Data Modeling Guide

## dbt Model Architecture

### Layer Structure
Our dbt project follows a three-layer architecture:

```
Raw Data → Staging → Intermediate → Marts
    ↓         ↓           ↓          ↓
  Sources   Clean    Business    Analytics
           & Cast    Logic      Ready
```

### Naming Conventions

#### Staging Models (`models/staging/`)
- **Purpose**: Clean and standardize raw data
- **Naming**: `stg_<source>_<table>`
- **Examples**: `stg_postgres_users`, `stg_snowflake_transactions`
- **Materialization**: Views (for performance and freshness)

```sql
-- Example: stg_users.sql
{{ config(materialized='view', tags=['staging']) }}

select
    user_id,
    lower(trim(email)) as email,
    initcap(first_name) as first_name,
    initcap(last_name) as last_name,
    -- Standardize and clean data
    current_timestamp as _loaded_at
from {{ source('raw', 'users') }}
```

#### Intermediate Models (`models/intermediate/`)
- **Purpose**: Business logic and complex transformations
- **Naming**: `int_<business_concept>`
- **Examples**: `int_user_metrics`, `int_product_performance`
- **Materialization**: Tables (for performance of complex logic)

```sql
-- Example: int_user_metrics.sql
{{ config(materialized='table', tags=['intermediate']) }}

with user_transactions as (
    select
        user_id,
        count(*) as total_transactions,
        sum(total_amount) as total_revenue,
        -- Complex business calculations
    from {{ ref('stg_transactions') }}
    group by user_id
)
-- Additional business logic
```

#### Marts Models (`models/marts/`)
- **Purpose**: Analytics-ready dimensional models
- **Naming**: `dim_<entity>`, `fact_<event>`, `mart_<business_area>`
- **Examples**: `dim_users`, `fact_transactions`, `mart_sales_metrics`
- **Materialization**: Tables (for query performance)

### Data Types and Standards

#### Consistent Data Types
```sql
-- Use consistent data types across models
user_id         VARCHAR(36)     -- UUIDs
email           VARCHAR(255)    -- Email addresses
amounts         DECIMAL(10,2)   -- Monetary values
percentages     DECIMAL(5,2)    -- Percentages (0.00-100.00)
timestamps      TIMESTAMP       -- All datetime fields
dates           DATE            -- Date-only fields
flags           BOOLEAN         -- True/false values
```

#### Null Handling
```sql
-- Always handle nulls explicitly
coalesce(total_revenue, 0) as total_revenue,
coalesce(last_login_date, '1900-01-01'::date) as last_login_date,

-- Use meaningful defaults
case 
    when last_login_date is null then 'never_logged_in'
    when last_login_date >= current_date - 7 then 'active'
    else 'inactive'
end as user_status
```

## Business Logic Patterns

### Customer Segmentation (RFM Analysis)
```sql
-- Standard RFM scoring pattern
with rfm_scores as (
    select
        user_id,
        -- Recency (days since last purchase)
        case 
            when recency_days <= 30 then 5
            when recency_days <= 60 then 4
            when recency_days <= 90 then 3
            when recency_days <= 180 then 2
            else 1
        end as recency_score,
        
        -- Frequency (number of purchases)
        case 
            when frequency >= 10 then 5
            when frequency >= 5 then 4
            when frequency >= 3 then 3
            when frequency >= 1 then 2
            else 1
        end as frequency_score,
        
        -- Monetary (total spend)
        case 
            when monetary_value >= 1000 then 5
            when monetary_value >= 500 then 4
            when monetary_value >= 200 then 3
            when monetary_value >= 50 then 2
            when monetary_value > 0 then 1
            else 0
        end as monetary_score
    from user_metrics
)
```

### Time-Based Calculations
```sql
-- Standard time dimension patterns
select
    -- Date parts
    date_trunc('month', created_at) as month_start,
    extract(year from created_at) as year,
    extract(quarter from created_at) as quarter,
    extract(dow from created_at) as day_of_week,
    
    -- Business time periods
    case 
        when extract(dow from created_at) in (0, 6) then 'weekend'
        else 'weekday'
    end as day_type,
    
    case 
        when extract(hour from created_at) between 6 and 11 then 'morning'
        when extract(hour from created_at) between 12 and 17 then 'afternoon'
        when extract(hour from created_at) between 18 and 21 then 'evening'
        else 'night'
    end as time_of_day
```

### Metric Calculations
```sql
-- Standard business metrics
select
    -- Conversion rates
    round(
        successful_transactions * 100.0 / nullif(total_transactions, 0), 
        2
    ) as conversion_rate_pct,
    
    -- Growth rates
    round(
        (current_period - previous_period) * 100.0 / nullif(previous_period, 0),
        2
    ) as growth_rate_pct,
    
    -- Running totals
    sum(revenue) over (
        partition by user_id 
        order by transaction_date 
        rows unbounded preceding
    ) as cumulative_revenue
```

## Testing Standards

### Required Tests
Every model must include appropriate tests:

```yaml
# models/schema.yml
models:
  - name: dim_users
    description: "User dimension with customer analytics"
    columns:
      - name: user_id
        description: "Unique user identifier"
        tests:
          - unique
          - not_null
      - name: email
        description: "User email address"
        tests:
          - unique
          - not_null
      - name: customer_segment
        description: "RFM-based customer segment"
        tests:
          - accepted_values:
              values: ['champions', 'loyal_customers', 'new_customers']
```

### Custom Business Tests
```sql
-- tests/assert_revenue_consistency.sql
-- Ensure revenue calculations are consistent across models
select
    abs(
        (select sum(total_revenue) from {{ ref('dim_users') }}) -
        (select sum(recognized_revenue) from {{ ref('fact_transactions') }})
    ) as revenue_difference
having revenue_difference > 1  -- Allow small rounding differences
```

## Performance Optimization

### Incremental Models
```sql
-- For large, append-only tables
{{ config(
    materialized='incremental',
    unique_key='transaction_id',
    on_schema_change='fail'
) }}

select * from {{ ref('stg_transactions') }}

{% if is_incremental() %}
    where created_at > (select max(created_at) from {{ this }})
{% endif %}
```

### Indexing Strategy
```sql
-- Add indexes for common query patterns
{{ config(
    post_hook="create index if not exists idx_users_email on {{ this }} (email)"
) }}
```

### Partitioning
```sql
-- For time-series data
{{ config(
    materialized='table',
    partition_by={
        "field": "transaction_date",
        "data_type": "date",
        "granularity": "month"
    }
) }}
```

## Documentation Standards

### Model Documentation
```sql
-- Every model should start with comprehensive documentation
{{
  config(
    materialized='table',
    description='User dimension table with comprehensive customer analytics and segmentation'
  )
}}

/*
This model creates a comprehensive user dimension that includes:
- Basic user profile information
- Transaction summary metrics
- RFM-based customer segmentation
- Engagement scoring
- Risk flags for churn prediction

Business Logic:
- Customer segments based on RFM analysis (Recency, Frequency, Monetary)
- Engagement score calculated from user activity patterns
- Churn risk flags based on inactivity periods

Data Sources:
- stg_users: User profile data
- stg_transactions: Transaction history
- stg_user_events: User behavior events

Update Frequency: Daily at 2 AM UTC
SLA: Must complete within 30 minutes
*/
```

### Column Documentation
```yaml
# Always document business meaning, not just technical details
columns:
  - name: customer_segment
    description: |
      RFM-based customer segmentation using recency, frequency, and monetary analysis.
      
      Segments:
      - champions: High value, recent, frequent customers
      - loyal_customers: Regular customers with good value
      - new_customers: Recent customers with potential
      - at_risk: Previously valuable customers showing decline
      
      Updated daily based on last 365 days of transaction history.
```

## Snowflake-Specific Patterns

### Warehouse Sizing
```sql
-- Use appropriate warehouse for different workloads
{{ config(
    pre_hook="use warehouse TRANSFORM_WH",  -- For heavy transformations
    post_hook="use warehouse QUERY_WH"     -- For lighter queries
) }}
```

### Clustering Keys
```sql
-- For large tables with common filter patterns
{{ config(
    cluster_by=['user_id', 'transaction_date']
) }}
```

### Time Travel
```sql
-- Leverage Snowflake's time travel for data recovery
select * from {{ ref('dim_users') }}
at (timestamp => '2024-01-01 00:00:00'::timestamp)
```

## Common Anti-Patterns to Avoid

### ❌ Don't Do This
```sql
-- Avoid SELECT *
select * from users;

-- Avoid complex nested CTEs without clear naming
with a as (select * from b), c as (select * from a)...

-- Avoid hardcoded values
where created_at >= '2024-01-01'

-- Avoid inconsistent naming
user_ID, UserEmail, user_created_date
```

### ✅ Do This Instead
```sql
-- Explicit column selection
select user_id, email, created_at from users;

-- Clear, descriptive CTE names
with active_users as (...), user_metrics as (...)

-- Use variables for dates
where created_at >= {{ var('start_date') }}

-- Consistent naming convention
user_id, user_email, user_created_date
```