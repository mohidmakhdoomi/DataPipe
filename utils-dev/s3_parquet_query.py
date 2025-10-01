#!/usr/bin/env python3
"""
S3 Parquet Query Tool for Data Ingestion Pipeline
Queries CDC data stored in S3 Parquet files from the data ingestion pipeline.
"""

import pandas as pd
import boto3
from datetime import datetime, timedelta
import argparse
import os
from typing import Optional, List
import pyarrow.parquet as pq
import pyarrow as pa
from botocore.exceptions import NoCredentialsError, ClientError

class S3ParquetQuery:
    def __init__(self, bucket_name: str, aws_profile: Optional[str] = None):
        """
        Initialize S3 Parquet Query tool
        
        Args:
            bucket_name: S3 bucket containing parquet files
            aws_profile: AWS profile to use (optional)
        """
        self.bucket_name = bucket_name
        
        # Initialize S3 client
        try:
            if aws_profile:
                session = boto3.Session(profile_name=aws_profile)
                self.s3_client = session.client('s3')
            else:
                self.s3_client = boto3.client('s3')
        except NoCredentialsError:
            print("AWS credentials not found. Please configure AWS CLI or set environment variables:")
            print("  AWS_ACCESS_KEY_ID")
            print("  AWS_SECRET_ACCESS_KEY")
            print("  AWS_DEFAULT_REGION")
            raise
    
    def list_tables(self) -> List[str]:
        """List available CDC tables in S3"""
        try:
            response = self.s3_client.list_objects_v2(
                Bucket=self.bucket_name,
                Prefix='topics/postgres.public.',
                Delimiter='/'
            )
            
            tables = []
            for prefix in response.get('CommonPrefixes', []):
                table_path = prefix['Prefix']
                table_name = table_path.split('.')[-1].rstrip('/')
                tables.append(table_name)
            
            return sorted(tables)
        except ClientError as e:
            print(f"Error listing tables: {e}")
            return []
    
    def get_partitions(self, table: str, days_back: int = 7) -> List[str]:
        """Get available partitions for a table"""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days_back)
        
        partitions = []
        current_date = start_date
        
        while current_date <= end_date:
            for hour in range(24):
                partition_path = f"topics/postgres.public.{table}/year={current_date.year}/month={current_date.month:02d}/day={current_date.day:02d}/hour={hour:02d}/"
                
                # Check if partition exists
                try:
                    response = self.s3_client.list_objects_v2(
                        Bucket=self.bucket_name,
                        Prefix=partition_path,
                        MaxKeys=1
                    )
                    if response.get('Contents'):
                        partitions.append(partition_path)
                except ClientError:
                    continue
            
            current_date += timedelta(days=1)
        
        return partitions
    
    def query_table(self, table: str, 
                   filters: Optional[dict] = None,
                   columns: Optional[List[str]] = None,
                   limit: Optional[int] = None,
                   days_back: int = 1) -> pd.DataFrame:
        """
        Query a CDC table from S3
        
        Args:
            table: Table name (e.g., 'users', 'products')
            filters: Dictionary of column filters
            columns: List of columns to select
            limit: Maximum number of rows to return
            days_back: Number of days to look back for data
        """
        print(f"Querying table: {table}")
        
        # Get partitions to query
        partitions = self.get_partitions(table, days_back)
        if not partitions:
            print(f"No data found for table {table} in the last {days_back} days")
            return pd.DataFrame()
        
        print(f"Found {len(partitions)} partitions to query")
        
        # Read data from all partitions
        dataframes = []
        for partition in partitions:
            try:
                s3_path = f"s3://{self.bucket_name}/{partition}"
                df_partition = pd.read_parquet(s3_path)
                if not df_partition.empty:
                    dataframes.append(df_partition)
            except Exception as e:
                print(f"Warning: Could not read partition {partition}: {e}")
                continue
        
        if not dataframes:
            print("No data found in any partitions")
            return pd.DataFrame()
        
        # Combine all partitions
        df = pd.concat(dataframes, ignore_index=True)
        print(f"Loaded {len(df)} total records")
        
        # Apply filters
        if filters:
            for column, value in filters.items():
                if column in df.columns:
                    if isinstance(value, list):
                        df = df[df[column].isin(value)]
                    else:
                        df = df[df[column] == value]
                    print(f"Applied filter {column}={value}, {len(df)} records remaining")
        
        # Select columns
        if columns:
            available_columns = [col for col in columns if col in df.columns]
            if available_columns:
                df = df[available_columns]
            else:
                print(f"Warning: None of the requested columns {columns} found in data")
        
        # Apply limit
        if limit and len(df) > limit:
            df = df.head(limit)
            print(f"Limited results to {limit} records")
        
        return df
    
    def get_deleted_records(self, table: str, days_back: int = 7) -> pd.DataFrame:
        """Get all deleted records for a table"""
        return self.query_table(
            table=table,
            filters={'__deleted': 'true'},
            days_back=days_back
        )
    
    def get_user_history(self, table: str, user_id: str, days_back: int = 30) -> pd.DataFrame:
        """Get complete change history for a specific user"""
        df = self.query_table(
            table=table,
            filters={'user_id': user_id},
            days_back=days_back
        )
        
        if not df.empty and '__ts_ms' in df.columns:
            df = df.sort_values('__ts_ms')
            # Convert timestamp to readable format
            df['timestamp'] = pd.to_datetime(df['__ts_ms'], unit='ms')
        
        return df
    
    def get_operation_summary(self, table: str, days_back: int = 1) -> pd.DataFrame:
        """Get summary of operations (INSERT, UPDATE, DELETE) for a table"""
        df = self.query_table(table=table, days_back=days_back)
        
        if df.empty or '__op' not in df.columns:
            return pd.DataFrame()
        
        # Map operation codes to readable names
        op_mapping = {
            'c': 'CREATE/INSERT',
            'u': 'UPDATE', 
            'd': 'DELETE',
            'r': 'READ/SNAPSHOT'
        }
        
        df['operation'] = df['__op'].map(op_mapping).fillna(df['__op'])
        
        summary = df.groupby('operation').agg({
            '__ts_ms': ['count', 'min', 'max']
        }).round(2)
        
        summary.columns = ['count', 'first_timestamp', 'last_timestamp']
        
        # Convert timestamps to readable format
        for col in ['first_timestamp', 'last_timestamp']:
            summary[col] = pd.to_datetime(summary[col], unit='ms')
        
        return summary.reset_index()


def main():
    parser = argparse.ArgumentParser(description='Query S3 Parquet files from data ingestion pipeline')
    parser.add_argument('--bucket', required=True, help='S3 bucket name')
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--table', help='Table to query (e.g., users, products)')
    parser.add_argument('--list-tables', action='store_true', help='List available tables')
    parser.add_argument('--deleted-only', action='store_true', help='Show only deleted records')
    parser.add_argument('--user-id', help='Get history for specific user ID')
    parser.add_argument('--summary', action='store_true', help='Show operation summary')
    parser.add_argument('--days', type=int, default=1, help='Number of days to look back (default: 1)')
    parser.add_argument('--limit', type=int, help='Limit number of results')
    parser.add_argument('--columns', help='Comma-separated list of columns to select')
    
    args = parser.parse_args()
    
    # Initialize query tool
    try:
        query_tool = S3ParquetQuery(args.bucket, args.profile)
    except Exception as e:
        print(f"Failed to initialize S3 connection: {e}")
        return 1
    
    # List tables
    if args.list_tables:
        tables = query_tool.list_tables()
        if tables:
            print("Available tables:")
            for table in tables:
                print(f"  - {table}")
        else:
            print("No tables found")
        return 0
    
    # Require table for other operations
    if not args.table:
        print("Please specify --table or use --list-tables")
        return 1
    
    # Parse columns
    columns = None
    if args.columns:
        columns = [col.strip() for col in args.columns.split(',')]
    
    try:
        # Execute query based on arguments
        if args.deleted_only:
            print(f"\n=== Deleted Records for {args.table} ===")
            df = query_tool.get_deleted_records(args.table, args.days)
        elif args.user_id:
            print(f"\n=== User History for {args.user_id} ===")
            df = query_tool.get_user_history(args.table, args.user_id, args.days)
        elif args.summary:
            print(f"\n=== Operation Summary for {args.table} ===")
            df = query_tool.get_operation_summary(args.table, args.days)
        else:
            print(f"\n=== All Records for {args.table} ===")
            df = query_tool.query_table(
                table=args.table,
                columns=columns,
                limit=args.limit,
                days_back=args.days
            )
        
        # Display results
        if df.empty:
            print("No data found")
        else:
            print(f"\nResults ({len(df)} records):")
            print("=" * 80)
            
            # Configure pandas display options
            pd.set_option('display.max_columns', None)
            pd.set_option('display.width', None)
            pd.set_option('display.max_colwidth', 50)
            
            print(df.to_string(index=False))
            
            # Show column info
            print(f"\nColumns: {list(df.columns)}")
            print(f"Data types:\n{df.dtypes}")
    
    except Exception as e:
        print(f"Query failed: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    exit(main())