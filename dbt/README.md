# dbt Data Transformations

This dbt project transforms raw transaction data into business-ready analytics tables.

## Project Structure

```
dbt/
├── models/
│   ├── staging/          # Raw data cleaning and standardization
│   │   ├── stg_users.sql
│   │   ├── stg_products.sql
│   │   ├── stg_transactions.sql
│   │   └── stg_user_events.sql
│   ├── intermediate/     # Business logic building blocks
│   │   ├── int_user_metrics.sql
│   │   ├── int_product_performance.sql
│   │   └── int_session_analytics.sql
│   └── marts/           # Final business tables
│       ├── dim_users.sql
│       ├── dim_products.sql
│       ├── fact_transactions.sql
│       └── mart_user_analytics.sql
├── macros/              # Reusable SQL functions
├── tests/               # Data quality tests
├── seeds/               # Reference data
└── snapshots/           # Slowly changing dimensions
```

## Data Models

### Staging Layer
- **stg_users**: Cleaned user profiles with standardized fields
- **stg_products**: Product catalog with calculated metrics
- **stg_transactions**: Transaction data with derived fields
- **stg_user_events**: Cleaned event stream data

### Intermediate Layer
- **int_user_metrics**: User behavior aggregations
- **int_product_performance**: Product sales metrics
- **int_session_analytics**: Session-level analytics

### Marts Layer
- **dim_users**: User dimension with segments and scores
- **dim_products**: Product dimension with categories
- **fact_transactions**: Transaction fact table
- **mart_user_analytics**: User analytics dashboard table

## Key Metrics

- Customer Lifetime Value (CLV)
- Monthly Active Users (MAU)
- Average Order Value (AOV)
- Product Performance Metrics
- User Segmentation
- Cohort Analysis

## Usage

```bash
# Run all models
dbt run

# Run specific model
dbt run --select stg_users

# Test data quality
dbt test

# Generate documentation
dbt docs generate
dbt docs serve
```