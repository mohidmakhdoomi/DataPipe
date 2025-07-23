#!/usr/bin/env python3
"""
Main ETL job for processing Kafka data through Spark
Reads from S3 (Kafka Connect output) and prepares data for Snowflake
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import os
import sys
import logging
from datetime import datetime, timedelta

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DataPipelineETL:
    """Main ETL class for processing data pipeline data"""
    
    def __init__(self):
        self.spark = self.create_spark_session()
        self.raw_bucket = os.getenv("S3_BUCKET_RAW", "data-lake-raw")
        self.processed_bucket = os.getenv("S3_BUCKET_PROCESSED", "data-lake-processed")
        
    def create_spark_session(self):
        """Create Spark session with optimized configuration"""
        return SparkSession.builder \
            .appName("DataPipelineETL") \
            .config("spark.sql.adaptive.enabled", "true") \
            .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
            .config("spark.sql.adaptive.skewJoin.enabled", "true") \
            .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
            .config("spark.hadoop.fs.s3a.aws.credentials.provider", 
                   "com.amazonaws.auth.DefaultAWSCredentialsProviderChain") \
            .config("spark.sql.parquet.compression.codec", "snappy") \
            .getOrCreate()
    
    def read_kafka_data(self):
        """Read data from S3 (Kafka Connect output)"""
        logger.info(f"Reading data from s3a://{self.raw_bucket}/kafka-data/")
        
        try:
            # Read transactions from Kafka Connect output
            transactions_path = f"s3a://{self.raw_bucket}/kafka-data/transactions/"
            transactions_df = self.spark.read \
                .option("multiline", "true") \
                .option("mode", "PERMISSIVE") \
                .json(transactions_path)
            
            # Read user events from Kafka Connect output  
            events_path = f"s3a://{self.raw_bucket}/kafka-data/user_events/"
            events_df = self.spark.read \
                .option("multiline", "true") \
                .option("mode", "PERMISSIVE") \
                .json(events_path)
            
            logger.info(f"Read {transactions_df.count()} transactions and {events_df.count()} events")
            return transactions_df, events_df
            
        except Exception as e:
            logger.error(f"Error reading Kafka data: {e}")
            raise
    
    def process_transactions(self, df):
        """Clean and enrich transaction data"""
        logger.info("Processing transactions data...")
        
        return df.filter(col("status").isNotNull()) \
                 .filter(col("total_amount") > 0) \
                 .withColumn("transaction_date", to_date(col("created_at"))) \
                 .withColumn("transaction_hour", hour(col("created_at"))) \
                 .withColumn("revenue_tier", 
                    when(col("total_amount") < 50, "Low")
                    .when(col("total_amount") < 200, "Medium")
                    .when(col("total_amount") < 500, "High")
                    .otherwise("Premium")) \
                 .withColumn("profit_margin", 
                    (col("total_amount") - col("discount_amount")) * 0.3) \
                 .withColumn("is_weekend", 
                    dayofweek(col("created_at")).isin([1, 7])) \
                 .withColumn("processing_timestamp", current_timestamp()) \
                 .dropDuplicates(["transaction_id"])
    
    def process_user_events(self, df):
        """Clean and enrich user event data"""
        logger.info("Processing user events data...")
        
        return df.filter(col("event_type").isNotNull()) \
                 .withColumn("event_date", to_date(col("timestamp"))) \
                 .withColumn("hour_of_day", hour(col("timestamp"))) \
                 .withColumn("is_mobile", col("device_type") == "mobile") \
                 .withColumn("is_purchase_event", col("event_type") == "purchase") \
                 .withColumn("is_weekend", 
                    dayofweek(col("timestamp")).isin([1, 7])) \
                 .withColumn("processing_timestamp", current_timestamp()) \
                 .dropDuplicates(["event_id"])
    
    def create_user_journey_analysis(self, events_df):
        """Create user journey analysis from events"""
        logger.info("Creating user journey analysis...")
        
        # Session-level aggregations
        session_metrics = events_df.groupBy("user_id", "session_id", "event_date") \
            .agg(
                count("*").alias("events_per_session"),
                countDistinct("event_type").alias("unique_event_types"),
                min("timestamp").alias("session_start"),
                max("timestamp").alias("session_end"),
                sum(when(col("event_type") == "purchase", 1).otherwise(0)).alias("purchases_in_session"),
                sum(when(col("event_type") == "add_to_cart", 1).otherwise(0)).alias("cart_additions"),
                first("device_type").alias("primary_device")
            ) \
            .withColumn("session_duration_minutes", 
                       (unix_timestamp("session_end") - unix_timestamp("session_start")) / 60)
        
        return session_metrics
    
    def create_daily_metrics(self, transactions_df, events_df):
        """Create comprehensive daily aggregated metrics"""
        logger.info("Creating daily metrics...")
        
        # Daily transaction metrics
        daily_transactions = transactions_df.groupBy("transaction_date", "user_id") \
            .agg(
                sum("total_amount").alias("daily_revenue"),
                count("*").alias("transaction_count"),
                avg("total_amount").alias("avg_transaction_value"),
                max("total_amount").alias("max_transaction_value"),
                sum("profit_margin").alias("daily_profit"),
                countDistinct("product_id").alias("unique_products_purchased")
            )
        
        # Daily event metrics
        daily_events = events_df.groupBy("event_date", "user_id") \
            .agg(
                count("*").alias("event_count"),
                countDistinct("session_id").alias("session_count"),
                sum(when(col("event_type") == "purchase", 1).otherwise(0)).alias("purchase_events"),
                sum(when(col("event_type") == "page_view", 1).otherwise(0)).alias("page_views"),
                sum(when(col("event_type") == "add_to_cart", 1).otherwise(0)).alias("cart_additions"),
                sum(when(col("is_mobile"), 1).otherwise(0)).alias("mobile_events")
            )
        
        # Join and create comprehensive daily metrics
        daily_metrics = daily_transactions.join(
            daily_events,
            (daily_transactions.transaction_date == daily_events.event_date) &
            (daily_transactions.user_id == daily_events.user_id),
            "full_outer"
        ).select(
            coalesce(daily_transactions.transaction_date, daily_events.event_date).alias("date"),
            coalesce(daily_transactions.user_id, daily_events.user_id).alias("user_id"),
            coalesce(col("daily_revenue"), lit(0)).alias("daily_revenue"),
            coalesce(col("transaction_count"), lit(0)).alias("transaction_count"),
            coalesce(col("avg_transaction_value"), lit(0)).alias("avg_transaction_value"),
            coalesce(col("max_transaction_value"), lit(0)).alias("max_transaction_value"),
            coalesce(col("daily_profit"), lit(0)).alias("daily_profit"),
            coalesce(col("unique_products_purchased"), lit(0)).alias("unique_products_purchased"),
            coalesce(col("event_count"), lit(0)).alias("event_count"),
            coalesce(col("session_count"), lit(0)).alias("session_count"),
            coalesce(col("purchase_events"), lit(0)).alias("purchase_events"),
            coalesce(col("page_views"), lit(0)).alias("page_views"),
            coalesce(col("cart_additions"), lit(0)).alias("cart_additions"),
            coalesce(col("mobile_events"), lit(0)).alias("mobile_events")
        ).withColumn("conversion_rate", 
                    when(col("page_views") > 0, col("purchase_events") / col("page_views"))
                    .otherwise(0))
        
        return daily_metrics
    
    def write_to_s3(self, df, path, partition_cols=None):
        """Write DataFrame to S3 in Parquet format with optional partitioning"""
        logger.info(f"Writing data to {path}")
        
        writer = df.coalesce(4) \
                   .write \
                   .mode("overwrite") \
                   .option("compression", "snappy")
        
        if partition_cols:
            writer = writer.partitionBy(*partition_cols)
        
        writer.parquet(path)
    
    def run_etl(self):
        """Main ETL execution method"""
        try:
            logger.info("Starting ETL job...")
            
            # Read raw data
            transactions_df, events_df = self.read_kafka_data()
            
            # Process data
            processed_transactions = self.process_transactions(transactions_df)
            processed_events = self.process_user_events(events_df)
            
            # Create analytics
            user_journey = self.create_user_journey_analysis(processed_events)
            daily_metrics = self.create_daily_metrics(processed_transactions, processed_events)
            
            # Write processed data to S3
            self.write_to_s3(
                processed_transactions, 
                f"s3a://{self.processed_bucket}/transactions/",
                ["transaction_date"]
            )
            
            self.write_to_s3(
                processed_events, 
                f"s3a://{self.processed_bucket}/user_events/",
                ["event_date"]
            )
            
            self.write_to_s3(
                user_journey,
                f"s3a://{self.processed_bucket}/user_journey/",
                ["event_date"]
            )
            
            self.write_to_s3(
                daily_metrics,
                f"s3a://{self.processed_bucket}/daily_metrics/",
                ["date"]
            )
            
            # Log summary statistics
            logger.info("ETL job completed successfully!")
            logger.info(f"Processed {processed_transactions.count()} transactions")
            logger.info(f"Processed {processed_events.count()} events")
            logger.info(f"Created {daily_metrics.count()} daily metric records")
            
        except Exception as e:
            logger.error(f"ETL job failed: {e}")
            raise
        finally:
            self.spark.stop()

def main():
    """Main entry point"""
    etl = DataPipelineETL()
    etl.run_etl()

if __name__ == "__main__":
    main()