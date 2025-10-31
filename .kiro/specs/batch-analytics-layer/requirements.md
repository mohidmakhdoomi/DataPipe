# Batch Analytics Layer - Requirements Document

## Introduction

This document outlines the requirements for a comprehensive batch analytics layer that processes e-commerce data from AWS S3 using Apache Iceberg, Spark batch processing, and loads results into Snowflake for business intelligence. The system includes dbt transformations for creating business-ready data marts and ensures eventual consistency with the speed layer.

The source data originates from a PostgreSQL database containing e-commerce transactional data that has been ingested into S3 through a data ingestion pipeline. The PostgreSQL schema includes four core tables: users (customer information), products (catalog data), orders (transaction headers), and order_items (transaction line items).

The pipeline will be designed for local development and deployment using Docker Desktop on Windows with Kubernetes (kind provisioner), while connecting to real cloud services (AWS S3 and Snowflake) for storage and data warehousing.

## Glossary

- **Batch_Analytics_System**: The comprehensive batch processing system that transforms PostgreSQL-sourced data from S3 into business intelligence insights
- **Source_PostgreSQL_Schema**: The original e-commerce database schema containing users, products, orders, and order_items tables
- **Users_Table**: Customer information table with id, email, first_name, last_name, and timestamps
- **Products_Table**: Product catalog table with id, name, description, price, stock_quantity, category, and timestamps
- **Orders_Table**: Transaction header table with id, user_id, status, total_amount, shipping_address, and timestamps
- **Order_Items_Table**: Transaction line items table with id, order_id, product_id, quantity, unit_price, and timestamps
- **Iceberg_Tables**: Apache Iceberg format tables stored in S3 for ACID transactions and schema evolution
- **Snowflake_Warehouse**: Cloud data warehouse with 3-layer architecture (Raw, Staging, Marts)
- **dbt_Transformations**: SQL-based transformations that create business-ready data models from raw PostgreSQL data

## Requirements

### Requirement 1: PostgreSQL Data Lake Processing with Iceberg

**User Story:** As a data engineer, I want to process PostgreSQL-sourced e-commerce data from S3 using Apache Iceberg table format, so that I can leverage ACID transactions and schema evolution for reliable batch processing of users, products, orders, and order_items data.

#### Acceptance Criteria

1. WHEN batch processing is required THEN the Batch_Analytics_System SHALL read PostgreSQL-sourced data from S3 using Iceberg table format
2. WHEN processing e-commerce data THEN Iceberg_Tables SHALL maintain referential integrity between Users_Table, Products_Table, Orders_Table, and Order_Items_Table
3. WHEN data is processed THEN Iceberg SHALL provide ACID transaction capabilities for all PostgreSQL table transformations
4. WHEN PostgreSQL schemas evolve THEN Iceberg SHALL handle schema evolution without data rewrites
5. WHEN time travel is needed THEN Iceberg SHALL support snapshot isolation and rollback for all e-commerce tables

### Requirement 2: PostgreSQL-Based Data Warehousing

**User Story:** As a business analyst, I want PostgreSQL-sourced e-commerce data loaded into Snowflake with a 3-layer architecture, so that I can perform complex analytical queries on customer, product, and transaction data for business intelligence reporting.

#### Acceptance Criteria

1. WHEN PostgreSQL data is loaded THEN the Snowflake_Warehouse SHALL implement a 3-layer architecture (Raw, Staging, Marts) for users, products, orders, and order_items
2. WHEN raw e-commerce data arrives THEN it SHALL be loaded into the Raw schema preserving original PostgreSQL table structures with metadata tracking
3. WHEN data cleaning is needed THEN the Staging schema SHALL provide validated Users_Table, Products_Table, Orders_Table, and Order_Items_Table with proper data types
4. WHEN business analytics are required THEN the Marts schema SHALL provide denormalized fact and dimension tables from PostgreSQL source data
5. WHEN query performance is critical THEN e-commerce tables SHALL use clustering keys on user_id, order_id, and product_id for optimization

### Requirement 3: PostgreSQL-Based dbt Transformations and Business Logic

**User Story:** As a data analyst, I want dbt transformations to create business-ready data marts from PostgreSQL e-commerce data, so that I can access clean, modeled customer, product, and transaction data for reporting and analysis.

#### Acceptance Criteria

1. WHEN transformations are needed THEN dbt_Transformations SHALL perform SQL-based transformations on PostgreSQL-sourced tables in Snowflake
2. WHEN business logic is applied THEN dbt SHALL implement customer lifetime value calculations using Users_Table and Orders_Table relationships
3. WHEN e-commerce analytics are required THEN dbt SHALL create fact tables joining Orders_Table with Order_Items_Table and Products_Table
4. WHEN data quality is required THEN dbt SHALL validate referential integrity between user_id, order_id, and product_id foreign keys
5. WHEN incremental updates are required THEN dbt SHALL support incremental processing based on PostgreSQL timestamp fields (created_at, updated_at)

### Requirement 4: Lambda Architecture Reconciliation

**User Story:** As a data architect, I want automated reconciliation between speed and batch layers, so that I can ensure eventual consistency and data accuracy across the Lambda Architecture.

#### Acceptance Criteria

1. WHEN reconciliation is performed THEN the system SHALL compare ClickHouse and Snowflake data
2. WHEN data discrepancies are found THEN the system SHALL alert and provide detailed reports
3. WHEN UUID conversion is needed THEN the system SHALL handle ClickHouse UUID to Snowflake STRING conversion
4. WHEN consistency validation runs THEN it SHALL check user sessions and transaction data
5. WHEN reconciliation completes THEN the system SHALL document convergence status and timing

### Requirement 5: Local Development Environment

**User Story:** As a developer, I want to run the batch layer locally using Docker Desktop on Windows with Kubernetes, so that I can develop and test batch processing without requiring full cloud infrastructure for all components.

#### Acceptance Criteria

1. WHEN deploying locally THEN the system SHALL run on Docker Desktop for Windows
2. WHEN using Kubernetes THEN the system SHALL use kind provisioner with Spark Operator
3. WHEN connecting to cloud services THEN the system SHALL connect to real AWS S3 and Snowflake instances
4. WHEN Spark batch jobs run THEN they SHALL execute on Kubernetes with proper resource allocation
5. WHEN running locally THEN the system SHALL require no more than 5Gi RAM for operation

### Requirement 6: PostgreSQL-Based E-commerce Business Intelligence

**User Story:** As a business stakeholder, I want comprehensive e-commerce analytics and KPIs derived from PostgreSQL transactional data, so that I can make data-driven decisions about customer behavior and business performance using actual user, product, and order data.

#### Acceptance Criteria

1. WHEN business metrics are calculated THEN the system SHALL provide customer lifetime value analytics using Users_Table and Orders_Table total_amount aggregations
2. WHEN product analysis is needed THEN the system SHALL calculate product performance metrics using Products_Table price, stock_quantity, and Order_Items_Table sales data
3. WHEN order behavior is analyzed THEN the system SHALL provide order status analysis using Orders_Table status transitions and shipping patterns
4. WHEN customer segmentation is required THEN the system SHALL segment customers based on Users_Table demographics and Orders_Table purchase behavior
5. WHEN inventory insights are needed THEN the system SHALL analyze Products_Table stock_quantity trends and Order_Items_Table demand patterns

### Requirement 7: PostgreSQL Data Quality and Governance

**User Story:** As a data governance officer, I want comprehensive data quality checks and governance controls for PostgreSQL-sourced e-commerce data, so that I can ensure data accuracy and compliance in the batch layer processing of customer, product, and transaction information.

#### Acceptance Criteria

1. WHEN PostgreSQL data is processed THEN the system SHALL validate Users_Table email uniqueness and Products_Table price constraints (>= 0)
2. WHEN business rules are violated THEN the system SHALL flag Orders_Table with invalid status values or negative total_amount
3. WHEN referential integrity is checked THEN the system SHALL validate Orders_Table user_id references Users_Table and Order_Items_Table references both Orders_Table and Products_Table
4. WHEN data lineage is required THEN the system SHALL track PostgreSQL table transformations from S3 ingestion through Snowflake marts
5. WHEN audit trails are needed THEN the system SHALL log all PostgreSQL schema changes and data transformations with timestamp tracking

### Requirement 8: Performance and Scalability

**User Story:** As a system administrator, I want the batch layer to be performant and cost-effective, so that it can handle large datasets efficiently while managing resource costs.

#### Acceptance Criteria

1. WHEN large datasets are processed THEN Spark SHALL optimize job execution with adaptive query execution
2. WHEN Snowflake warehouses are used THEN they SHALL auto-suspend to minimize costs
3. WHEN data volumes grow THEN the system SHALL scale processing resources appropriately
4. WHEN performance monitoring is active THEN the system SHALL track processing times and resource utilization
5. WHEN cost optimization is needed THEN the system SHALL provide recommendations for resource efficiency