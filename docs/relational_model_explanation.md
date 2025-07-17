# Relational Model Design (OLTP)

## Normalized Database Structure

### 1. Entity Tables

#### users (Customer Master)
- **Primary Key**: user_id (UUID)
- **Unique Constraints**: email
- **Business Rules**:
  - Email must be valid format
  - Registration date cannot be future
  - Tier must be: bronze, silver, gold, platinum
- **Indexes**: 
  - PRIMARY KEY (user_id)
  - UNIQUE INDEX (email)
  - INDEX (tier, is_active)
  - INDEX (registration_date)

#### products (Product Master)
- **Primary Key**: product_id (UUID)
- **Business Rules**:
  - Price must be positive
  - Cost must be non-negative
  - Name cannot be null
- **Indexes**:
  - PRIMARY KEY (product_id)
  - INDEX (category, subcategory)
  - INDEX (brand)
  - INDEX (is_active)

### 2. Transaction Tables

#### transactions (Order/Purchase Records)
- **Primary Key**: transaction_id (UUID)
- **Foreign Keys**: 
  - user_id → users.user_id
  - product_id → products.product_id
- **Business Rules**:
  - Quantity must be positive
  - Unit price must be positive
  - Total amount = (unit_price × quantity) - discount + tax
  - Status must be: pending, completed, failed, refunded
- **Indexes**:
  - PRIMARY KEY (transaction_id)
  - INDEX (user_id, created_at)
  - INDEX (product_id, created_at)
  - INDEX (status)
  - INDEX (created_at)

#### user_events (Behavioral Tracking)
- **Primary Key**: event_id (UUID)
- **Foreign Keys**:
  - user_id → users.user_id
  - product_id → products.product_id (nullable)
- **Business Rules**:
  - Event type must be valid enum
  - Timestamp cannot be future
  - Session ID groups related events
- **Indexes**:
  - PRIMARY KEY (event_id)
  - INDEX (user_id, timestamp)
  - INDEX (session_id)
  - INDEX (event_type, timestamp)
  - INDEX (product_id) WHERE product_id IS NOT NULL

## Normalization Level: 3NF (Third Normal Form)

### 1st Normal Form (1NF) ✅
- All attributes contain atomic values
- No repeating groups
- Each row is unique

### 2nd Normal Form (2NF) ✅
- Meets 1NF requirements
- No partial dependencies on composite keys
- All non-key attributes depend on entire primary key

### 3rd Normal Form (3NF) ✅
- Meets 2NF requirements
- No transitive dependencies
- Non-key attributes depend only on primary key

## ACID Properties

### Atomicity
- Each transaction is all-or-nothing
- Failed transactions are rolled back completely
- Referential integrity maintained

### Consistency
- Database constraints enforced
- Foreign key relationships maintained
- Business rules validated

### Isolation
- Concurrent transactions don't interfere
- Read committed isolation level
- Prevents dirty reads and phantom reads

### Durability
- Committed transactions persist
- Write-ahead logging (WAL)
- Point-in-time recovery available

## Referential Integrity

### Foreign Key Constraints
```sql
-- Transaction references valid user
ALTER TABLE transactions 
ADD CONSTRAINT fk_transactions_user_id 
FOREIGN KEY (user_id) REFERENCES users(user_id);

-- Transaction references valid product
ALTER TABLE transactions 
ADD CONSTRAINT fk_transactions_product_id 
FOREIGN KEY (product_id) REFERENCES products(product_id);

-- Event references valid user
ALTER TABLE user_events 
ADD CONSTRAINT fk_user_events_user_id 
FOREIGN KEY (user_id) REFERENCES users(user_id);

-- Event optionally references product
ALTER TABLE user_events 
ADD CONSTRAINT fk_user_events_product_id 
FOREIGN KEY (product_id) REFERENCES products(product_id);
```

### Cascade Rules
- **ON DELETE RESTRICT**: Prevent deletion of referenced records
- **ON UPDATE CASCADE**: Update foreign keys when primary key changes
- **Orphan Prevention**: No transactions without valid users/products

## Indexing Strategy

### Primary Indexes (Clustered)
- **users**: Clustered on user_id (UUID)
- **products**: Clustered on product_id (UUID)
- **transactions**: Clustered on transaction_id (UUID)
- **user_events**: Clustered on event_id (UUID)

### Secondary Indexes (Non-Clustered)
- **Performance**: Query optimization
- **Uniqueness**: Business rule enforcement
- **Foreign Keys**: Join performance

### Composite Indexes
```sql
-- Multi-column indexes for common query patterns
CREATE INDEX idx_transactions_user_date 
ON transactions(user_id, created_at);

CREATE INDEX idx_events_user_session 
ON user_events(user_id, session_id, timestamp);

CREATE INDEX idx_products_category_active 
ON products(category, is_active);
```

## Data Types and Constraints

### UUID Primary Keys
- **Advantages**: Globally unique, no collision risk
- **Disadvantages**: Larger storage, random access pattern
- **Alternative**: BIGINT with sequences for better performance

### Timestamp Handling
- **created_at**: Record creation time (immutable)
- **updated_at**: Last modification time (auto-updated)
- **Timezone**: UTC storage, local display

### JSON/JSONB for Properties
- **user_events.properties**: Flexible event metadata
- **Advantages**: Schema flexibility, no additional tables
- **Disadvantages**: Limited query capabilities, no referential integrity

## Triggers and Stored Procedures

### Audit Triggers
```sql
-- Auto-update timestamp trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply to all tables with updated_at
CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

### Business Logic Triggers
```sql
-- Validate transaction totals
CREATE OR REPLACE FUNCTION validate_transaction_total()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.total_amount != (NEW.unit_price * NEW.quantity) - NEW.discount_amount + NEW.tax_amount THEN
        RAISE EXCEPTION 'Transaction total calculation error';
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';
```

## Performance Considerations

### Query Optimization
- **Selective Indexes**: Cover common WHERE clauses
- **Covering Indexes**: Include SELECT columns
- **Partial Indexes**: Filter on common conditions

### Partitioning Strategy
```sql
-- Partition transactions by date for performance
CREATE TABLE transactions_2024_01 PARTITION OF transactions
FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

CREATE TABLE transactions_2024_02 PARTITION OF transactions
FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
```

### Connection Pooling
- **pgBouncer**: Connection pooling for PostgreSQL
- **Max Connections**: Limit concurrent connections
- **Statement Timeout**: Prevent long-running queries

## Backup and Recovery

### Point-in-Time Recovery
- **WAL Archiving**: Continuous backup
- **Base Backups**: Full database snapshots
- **Recovery**: Restore to any point in time

### Replication
- **Streaming Replication**: Real-time standby servers
- **Read Replicas**: Scale read operations
- **Failover**: Automatic promotion of standby