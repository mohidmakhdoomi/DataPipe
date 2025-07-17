-- Create analytics database and tables for real-time data

CREATE DATABASE IF NOT EXISTS analytics;

-- User events table for real-time analytics
CREATE TABLE IF NOT EXISTS analytics.user_events (
    event_id String,
    user_id String,
    session_id String,
    event_type String,
    timestamp DateTime64(3),
    page_url Nullable(String),
    product_id Nullable(String),
    search_query Nullable(String),
    device_type String,
    browser String,
    ip_address String,
    properties String,
    date Date MATERIALIZED toDate(timestamp)
) ENGINE = MergeTree()
PARTITION BY date
ORDER BY (timestamp, user_id, event_type)
TTL timestamp + INTERVAL 1 YEAR;

-- Transactions table for real-time transaction analytics
CREATE TABLE IF NOT EXISTS analytics.transactions (
    transaction_id String,
    user_id String,
    product_id String,
    quantity UInt32,
    unit_price Decimal(10,2),
    total_amount Decimal(10,2),
    discount_amount Decimal(10,2),
    tax_amount Decimal(10,2),
    status String,
    payment_method String,
    created_at DateTime64(3),
    date Date MATERIALIZED toDate(created_at)
) ENGINE = MergeTree()
PARTITION BY date
ORDER BY (created_at, user_id, transaction_id)
TTL created_at + INTERVAL 2 YEARS;

-- Materialized view for real-time metrics
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.hourly_metrics
ENGINE = SummingMergeTree()
PARTITION BY toYYYYMM(hour)
ORDER BY (hour, event_type)
AS SELECT
    toStartOfHour(timestamp) as hour,
    event_type,
    count() as event_count,
    uniq(user_id) as unique_users,
    uniq(session_id) as unique_sessions
FROM analytics.user_events
GROUP BY hour, event_type;

-- Create Kafka engine tables for real-time ingestion
CREATE TABLE IF NOT EXISTS analytics.user_events_queue (
    event_id String,
    user_id String,
    session_id String,
    event_type String,
    timestamp DateTime64(3),
    page_url Nullable(String),
    product_id Nullable(String),
    search_query Nullable(String),
    device_type String,
    browser String,
    ip_address String,
    properties String
) ENGINE = Kafka()
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'user_events',
    kafka_group_name = 'clickhouse_consumer',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 3;

-- Materialized view to move data from Kafka to main table
CREATE MATERIALIZED VIEW IF NOT EXISTS analytics.user_events_mv TO analytics.user_events AS
SELECT * FROM analytics.user_events_queue;