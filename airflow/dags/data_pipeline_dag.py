"""
Main data pipeline DAG for orchestrating the entire data flow
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.amazon.aws.operators.s3 import S3CreateBucketOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor

# Default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'catchup': False,
}

# DAG definition
dag = DAG(
    'data_pipeline_legacy',
    default_args=default_args,
    description='Legacy data pipeline orchestration (deprecated)',
    schedule_interval=None,  # Disabled
    max_active_runs=1,
    tags=['data-pipeline', 'etl', 'legacy', 'deprecated'],
)

def extract_data(**context):
    """Extract data from various sources"""
    print("Extracting data from sources...")
    # This will be implemented with actual extraction logic
    return "extraction_complete"

def validate_data(**context):
    """Validate data quality"""
    print("Validating data quality...")
    # Great Expectations validation will go here
    return "validation_complete"

def transform_data(**context):
    """Transform data using dbt"""
    print("Running dbt transformations...")
    # dbt run commands will go here
    return "transformation_complete"

def load_to_warehouse(**context):
    """Load data to Snowflake"""
    from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
    print("Loading data to Snowflake...")
    
    # This would typically involve:
    # 1. Copy data from S3 to Snowflake staging tables
    # 2. Run dbt transformations in Snowflake
    # 3. Update data marts
    
    return "load_complete"

def run_dbt_snowflake(**context):
    """Run dbt transformations in Snowflake"""
    from airflow.operators.bash import BashOperator
    print("Running dbt transformations in Snowflake...")
    
    # This would run: dbt run --target snowflake
    return "dbt_snowflake_complete"

def update_clickhouse(**context):
    """Update ClickHouse for real-time analytics"""
    import os
    from airflow.models import Variable
    
    # Get ClickHouse connection details
    clickhouse_host = Variable.get("clickhouse_host", default_var=os.getenv('CLICKHOUSE_HOST', 'clickhouse.data-storage.svc.cluster.local'))
    clickhouse_port = Variable.get("clickhouse_port", default_var=os.getenv('CLICKHOUSE_PORT', '8123'))
    
    print(f"Updating ClickHouse at {clickhouse_host}:{clickhouse_port}...")
    # ClickHouse update logic would go here
    return "clickhouse_updated"

# Task definitions
extract_task = PythonOperator(
    task_id='extract_data',
    python_callable=extract_data,
    dag=dag,
)

validate_task = PythonOperator(
    task_id='validate_data',
    python_callable=validate_data,
    dag=dag,
)

transform_task = PythonOperator(
    task_id='transform_data',
    python_callable=transform_data,
    dag=dag,
)

dbt_snowflake_task = PythonOperator(
    task_id='run_dbt_snowflake',
    python_callable=run_dbt_snowflake,
    dag=dag,
)

load_warehouse_task = PythonOperator(
    task_id='load_to_warehouse',
    python_callable=load_to_warehouse,
    dag=dag,
)

update_clickhouse_task = PythonOperator(
    task_id='update_clickhouse',
    python_callable=update_clickhouse,
    dag=dag,
)

# Task dependencies
extract_task >> validate_task >> transform_task >> dbt_snowflake_task >> [load_warehouse_task, update_clickhouse_task]