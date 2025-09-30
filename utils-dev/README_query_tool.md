# S3 Parquet Query Tool

A Python script for ad-hoc querying of CDC data stored in S3 Parquet files from your data ingestion pipeline.

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. Configure AWS credentials (choose one):
```bash
# Option 1: AWS CLI
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1

# Option 3: Use AWS profile
aws configure --profile myprofile
```

## Usage Examples

### List Available Tables
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --list-tables
```

### Query All Records from Users Table
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --days 7 --limit 100
```

### Get Only Deleted Records
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --deleted-only --days 30
```

### Get User Change History
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --user-id "550e8400-e29b-41d4-a716-446655440000" --days 30
```

### Get Operation Summary
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --summary --days 7
```

### Select Specific Columns
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --columns "user_id,email,__op,__deleted,__ts_ms" --limit 50
```

### Use AWS Profile
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --profile myprofile --days 1
```

## Command Line Options

- `--bucket`: S3 bucket name (required)
- `--table`: Table to query (users, products, etc.)
- `--list-tables`: List all available tables
- `--deleted-only`: Show only deleted records
- `--user-id`: Get complete history for specific user
- `--summary`: Show operation summary (INSERT/UPDATE/DELETE counts)
- `--days`: Number of days to look back (default: 1)
- `--limit`: Maximum number of records to return
- `--columns`: Comma-separated list of columns to select
- `--profile`: AWS profile to use

## Data Structure

The CDC records in S3 contain these key fields:

### Original Table Fields
- `user_id`, `email`, `first_name`, `last_name`, `tier`, etc.

### CDC Metadata Fields
- `__op`: Operation type (`c`=create, `u`=update, `d`=delete, `r`=read/snapshot)
- `__deleted`: Boolean indicating if record was deleted
- `__ts_ms`: Timestamp in milliseconds when change occurred

### Partition Fields
- `year`, `month`, `day`, `hour`: Time-based partitioning

## Examples of What You Can Query

### Find All Users Deleted Today
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --deleted-only --days 1
```

### Track a User's Journey
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --user-id "your-user-id" --days 30
```

### Monitor Data Quality
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --summary --days 7
```

### Export Specific Data
```bash
python s3_parquet_query.py --bucket datapipe-ingestion-123 --table users --columns "user_id,email,tier,__op" --days 7 > user_changes.txt
```

## Troubleshooting

### No Data Found
- Check if the bucket name is correct
- Verify the table name exists using `--list-tables`
- Try increasing `--days` parameter
- Check AWS credentials and permissions

### Permission Errors
- Ensure your AWS credentials have S3 read permissions
- Verify bucket policy allows your IAM user/role to access the data

### Memory Issues with Large Datasets
- Use `--limit` to restrict result size
- Reduce `--days` parameter
- Select specific `--columns` instead of all columns

## Performance Tips

- Use `--limit` for large datasets
- Select only needed columns with `--columns`
- Query recent data first (smaller `--days` values)
- The tool automatically handles partitioning for efficient queries