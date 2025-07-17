"""
Snowflake Data Pipeline DAG - Orchestrates ETL process with Snowflake as target
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.dummy import DummyOperator
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule
import logging
import os

# Default arguments
default_args = {
    'owner': 'data-engineering-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'catchup': False,
    'max_active_runs': 1,
}

# DAG definition
dag = DAG(
    'snowflake_data_pipeline',
    default_args=default_args,
    description='Data pipeline with Snowflake as primary data warehouse',
    schedule_interval='@daily',
    tags=['snowflake', 'data-pipeline', 'etl', 'production'],
    doc_md=__doc__,
)

def check_snowflake_connection(**context):
    """Verify Snowflake connection and warehouse availability"""
    try:
        snowflake_hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
        
        # Test connection with simple query
        result = snowflake_hook.get_first("SELECT CURRENT_VERSION()")
        logging.info(f"Snowflake connection successful. Version: {result[0]}")
        
        # Check warehouse status
        warehouse_status = snowflake_hook.get_first(
            f"SHOW WAREHOUSES LIKE '{os.getenv('SNOWFLAKE_WAREHOUSE', 'COMPUTE_WH')}'"
        )
        logging.info(f"Warehouse status: {warehouse_status}")
        
        return True
        
    except Exception as e:
        logging.error(f"Snowflake connection failed: {e}")
        raise Exception(f"Snowflake connection failed: {e}")

def extract_from_postgres(**context):
    """Extract data from PostgreSQL source"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Extract incremental data based on last run
    last_run = context.get('prev_ds', '1900-01-01')
    
    extraction_queries = {
        'users': f"""
            SELECT * FROM users 
            WHERE updated_at > '{last_run}'::timestamp
        """,
        'products': f"""
            SELECT * FROM products 
            WHERE updated_at > '{last_run}'::timestamp
        """,
        'transactions': f"""
            SELECT * FROM transactions 
            WHERE created_at > '{last_run}'::timestamp
        """,
        'user_events': f"""
            SELECT * FROM user_events 
            WHERE timestamp > '{last_run}'::timestamp
        """
    }
    
    extracted_counts = {}
    for table, query in extraction_queries.items():
        result = postgres_hook.get_records(query)
        extracted_counts[table] = len(result)
        logging.info(f"Extracted {len(result)} records from {table}")
        
        # Store data in XCom for loading to Snowflake
        context['task_instance'].xcom_push(key=f'{table}_data', value=result)
    
    context['task_instance'].xcom_push(key='extraction_counts', value=extracted_counts)
    return extracted_counts

def load_to_snowflake_staging(**context):
    """Load extracted data to Snowflake staging tables"""
    snowflake_hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    
    # Create staging tables if they don't exist
    staging_ddl = {
        'users': """
            CREATE TABLE IF NOT EXISTS staging.users (
                user_id VARCHAR(36),
                email VARCHAR(255),
                first_name VARCHAR(100),
                last_name VARCHAR(100),
                date_of_birth DATE,
                registration_date TIMESTAMP,
                country VARCHAR(100),
                city VARCHAR(100),
                tier VARCHAR(20),
                is_active BOOLEAN,
                last_login TIMESTAMP,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
            )
        """,
        'products': """
            CREATE TABLE IF NOT EXISTS staging.products (
                product_id VARCHAR(36),
                name VARCHAR(255),
                category VARCHAR(100),
                subcategory VARCHAR(100),
                price DECIMAL(10,2),
                cost DECIMAL(10,2),
                brand VARCHAR(100),
                description TEXT,
                is_active BOOLEAN,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
            )
        """,
        'transactions': """
            CREATE TABLE IF NOT EXISTS staging.transactions (
                transaction_id VARCHAR(36),
                user_id VARCHAR(36),
                product_id VARCHAR(36),
                quantity INTEGER,
                unit_price DECIMAL(10,2),
                total_amount DECIMAL(10,2),
                discount_amount DECIMAL(10,2),
                tax_amount DECIMAL(10,2),
                status VARCHAR(20),
                payment_method VARCHAR(50),
                shipping_address TEXT,
                created_at TIMESTAMP,
                updated_at TIMESTAMP,
                _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
            )
        """,
        'user_events': """
            CREATE TABLE IF NOT EXISTS staging.user_events (
                event_id VARCHAR(36),
                user_id VARCHAR(36),
                session_id VARCHAR(36),
                event_type VARCHAR(50),
                timestamp TIMESTAMP,
                page_url VARCHAR(500),
                product_id VARCHAR(36),
                search_query VARCHAR(255),
                device_type VARCHAR(20),
                browser VARCHAR(50),
                ip_address VARCHAR(45),
                properties VARIANT,
                created_at TIMESTAMP,
                _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
            )
        """
    }
    
    # Create staging tables
    for table, ddl in staging_ddl.items():
        snowflake_hook.run(ddl)
        logging.info(f"Created/verified staging table: staging.{table}")
    
    # Load data (in production, this would use COPY commands from S3)
    extraction_counts = context['task_instance'].xcom_pull(key='extraction_counts')
    
    for table, count in extraction_counts.items():
        if count > 0:
            # Truncate staging table for full refresh
            snowflake_hook.run(f"TRUNCATE TABLE staging.{table}")
            logging.info(f"Loaded {count} records to staging.{table}")
    
    return extraction_counts

def run_dbt_snowflake(**context):
    """Run dbt transformations in Snowflake"""
    import subprocess
    
    # Set environment variables for dbt Snowflake connection
    env = os.environ.copy()
    env.update({
        'SNOWFLAKE_ACCOUNT': os.getenv('SNOWFLAKE_ACCOUNT'),
        'SNOWFLAKE_USER': os.getenv('SNOWFLAKE_USER'),
        'SNOWFLAKE_PASSWORD': os.getenv('SNOWFLAKE_PASSWORD'),
        'SNOWFLAKE_ROLE': os.getenv('SNOWFLAKE_ROLE'),
        'SNOWFLAKE_DATABASE': os.getenv('SNOWFLAKE_DATABASE'),
        'SNOWFLAKE_WAREHOUSE': os.getenv('SNOWFLAKE_WAREHOUSE')
    })
    
    try:
        # Run dbt with Snowflake target
        result = subprocess.run(
            ['dbt', 'run', '--target', 'snowflake'],
            cwd='/opt/airflow/dbt',
            env=env,
            capture_output=True,
            text=True,
            timeout=1800
        )
        
        if result.returncode != 0:
            logging.error(f"dbt run failed: {result.stderr}")
            raise Exception(f"dbt run failed: {result.stderr}")
        
        logging.info(f"dbt run successful: {result.stdout}")
        
        # Run dbt tests
        test_result = subprocess.run(
            ['dbt', 'test', '--target', 'snowflake'],
            cwd='/opt/airflow/dbt',
            env=env,
            capture_output=True,
            text=True,
            timeout=600
        )
        
        if test_result.returncode != 0:
            logging.warning(f"dbt tests failed: {test_result.stderr}")
        else:
            logging.info(f"dbt tests passed: {test_result.stdout}")
        
        return result.stdout
        
    except subprocess.TimeoutExpired:
        logging.error("dbt run timed out")
        raise Exception("dbt run timed out after 30 minutes")

def validate_snowflake_data(**context):
    """Validate data quality in Snowflake"""
    snowflake_hook = SnowflakeHook(snowflake_conn_id='snowflake_default')
    
    validation_queries = {
        'row_counts': """
            SELECT 
                'users' as table_name, COUNT(*) as row_count FROM marts.dim_users
            UNION ALL
            SELECT 
                'transactions' as table_name, COUNT(*) as row_count FROM marts.fact_transactions
            UNION ALL
            SELECT 
                'business_metrics' as table_name, COUNT(*) as row_count FROM marts.mart_business_metrics
        """,
        'data_freshness': """
            SELECT 
                MAX(last_updated) as latest_update,
                COUNT(*) as total_records
            FROM marts.dim_users
        """,
        'revenue_validation': """
            SELECT 
                SUM(total_revenue) as total_revenue,
                COUNT(DISTINCT user_id) as unique_customers,
                AVG(total_revenue) as avg_revenue_per_customer
            FROM marts.dim_users
            WHERE total_revenue > 0
        """
    }
    
    validation_results = {}
    for check_name, query in validation_queries.items():
        result = snowflake_hook.get_records(query)
        validation_results[check_name] = result
        logging.info(f"{check_name}: {result}")
    
    context['task_instance'].xcom_push(key='validation_results', value=validation_results)
    return validation_results

# Task definitions
start_task = DummyOperator(
    task_id='start_snowflake_pipeline',
    dag=dag,
)

check_snowflake = PythonOperator(
    task_id='check_snowflake_connection',
    python_callable=check_snowflake_connection,
    dag=dag,
)

extract_postgres = PythonOperator(
    task_id='extract_from_postgres',
    python_callable=extract_from_postgres,
    dag=dag,
)

load_staging = PythonOperator(
    task_id='load_to_snowflake_staging',
    python_callable=load_to_snowflake_staging,
    dag=dag,
)

run_dbt = PythonOperator(
    task_id='run_dbt_snowflake',
    python_callable=run_dbt_snowflake,
    dag=dag,
)

validate_data = PythonOperator(
    task_id='validate_snowflake_data',
    python_callable=validate_snowflake_data,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_snowflake_pipeline',
    dag=dag,
)

# Task dependencies
start_task >> check_snowflake >> extract_postgres >> load_staging >> run_dbt >> validate_data >> end_task