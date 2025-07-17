"""
Main Data Pipeline DAG - Orchestrates the complete ETL process
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator, BranchPythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.dummy import DummyOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.providers.amazon.aws.operators.s3 import S3CreateObjectOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.http.sensors.http import HttpSensor
from airflow.providers.http.operators.http import SimpleHttpOperator
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule
from airflow.models import Variable
import pandas as pd
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
    'data_pipeline_main',
    default_args=default_args,
    description='Main data pipeline orchestrating complete ETL process',
    schedule_interval='@hourly',
    tags=['data-pipeline', 'etl', 'production', 'main'],
    doc_md=__doc__,
)

def check_data_freshness(**context):
    """Check if source data is fresh enough to proceed"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Check latest transaction timestamp
    sql = """
    SELECT 
        MAX(created_at) as latest_transaction,
        COUNT(*) as total_records,
        COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 hour' THEN 1 END) as recent_records
    FROM transactions
    """
    
    result = postgres_hook.get_first(sql)
    latest_transaction, total_records, recent_records = result
    
    logging.info(f"Latest transaction: {latest_transaction}")
    logging.info(f"Total records: {total_records}")
    logging.info(f"Recent records (last hour): {recent_records}")
    
    # Store metrics in XCom for downstream tasks
    context['task_instance'].xcom_push(key='data_freshness_metrics', value={
        'latest_transaction': str(latest_transaction),
        'total_records': total_records,
        'recent_records': recent_records,
        'is_fresh': recent_records > 0
    })
    
    return recent_records > 0

def extract_and_validate_data(**context):
    """Extract data from source systems and perform basic validation"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Extract data with quality checks
    extraction_queries = {
        'users': """
            SELECT 
                COUNT(*) as total_users,
                COUNT(CASE WHEN is_active THEN 1 END) as active_users,
                COUNT(CASE WHEN email IS NULL OR email = '' THEN 1 END) as invalid_emails
            FROM users
        """,
        'products': """
            SELECT 
                COUNT(*) as total_products,
                COUNT(CASE WHEN is_active THEN 1 END) as active_products,
                COUNT(CASE WHEN price <= 0 THEN 1 END) as invalid_prices
            FROM products
        """,
        'transactions': """
            SELECT 
                COUNT(*) as total_transactions,
                COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_transactions,
                SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 hour' THEN 1 END) as recent_transactions
            FROM transactions
        """,
        'user_events': """
            SELECT 
                COUNT(*) as total_events,
                COUNT(DISTINCT user_id) as unique_users,
                COUNT(DISTINCT session_id) as unique_sessions,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '1 hour' THEN 1 END) as recent_events
            FROM user_events
        """
    }
    
    extraction_results = {}
    for table, query in extraction_queries.items():
        result = postgres_hook.get_first(query)
        extraction_results[table] = dict(zip(
            [desc[0] for desc in postgres_hook.get_conn().cursor().description],
            result
        ))
        logging.info(f"{table} metrics: {extraction_results[table]}")
    
    # Data quality validation
    quality_issues = []
    
    # Check for invalid emails
    if extraction_results['users']['invalid_emails'] > 0:
        quality_issues.append(f"Found {extraction_results['users']['invalid_emails']} users with invalid emails")
    
    # Check for invalid prices
    if extraction_results['products']['invalid_prices'] > 0:
        quality_issues.append(f"Found {extraction_results['products']['invalid_prices']} products with invalid prices")
    
    # Check for data freshness
    if extraction_results['transactions']['recent_transactions'] == 0:
        quality_issues.append("No recent transactions found in the last hour")
    
    if quality_issues:
        logging.warning(f"Data quality issues detected: {quality_issues}")
        context['task_instance'].xcom_push(key='quality_issues', value=quality_issues)
    
    context['task_instance'].xcom_push(key='extraction_results', value=extraction_results)
    return extraction_results

def decide_processing_path(**context):
    """Decide whether to run full or incremental processing"""
    extraction_results = context['task_instance'].xcom_pull(key='extraction_results')
    
    # Decision logic based on data volume and freshness
    recent_transactions = extraction_results['transactions']['recent_transactions']
    total_transactions = extraction_results['transactions']['total_transactions']
    
    if recent_transactions > 1000:  # High volume
        return 'processing.full_processing'
    elif recent_transactions > 0:   # Normal volume
        return 'processing.incremental_processing'
    else:                          # No new data
        return 'processing.skip_processing'

def run_dbt_models(**context):
    """Run dbt transformations"""
    import subprocess
    import os
    
    # Set environment variables for dbt
    env = os.environ.copy()
    env.update({
        'POSTGRES_HOST': os.getenv('POSTGRES_HOST', 'postgres-data'),  # For local docker-compose
        'POSTGRES_PORT': os.getenv('POSTGRES_PORT', '5432'),
        'POSTGRES_DB': os.getenv('POSTGRES_DB', 'transactions_db'),
        'POSTGRES_USER': os.getenv('POSTGRES_USER', 'postgres'),
        'POSTGRES_PASSWORD': os.getenv('POSTGRES_PASSWORD', ''),
        'SNOWFLAKE_ACCOUNT': os.getenv('SNOWFLAKE_ACCOUNT', ''),
        'SNOWFLAKE_USER': os.getenv('SNOWFLAKE_USER', ''),
        'SNOWFLAKE_PASSWORD': os.getenv('SNOWFLAKE_PASSWORD', ''),
        'SNOWFLAKE_ROLE': os.getenv('SNOWFLAKE_ROLE', ''),
        'SNOWFLAKE_DATABASE': os.getenv('SNOWFLAKE_DATABASE', ''),
        'SNOWFLAKE_WAREHOUSE': os.getenv('SNOWFLAKE_WAREHOUSE', '')
    })
    
    try:
        # Determine target based on environment
        target = 'snowflake' if env.get('SNOWFLAKE_ACCOUNT') else 'dev'
        
        # Run dbt models
        result = subprocess.run(
            ['dbt', 'run', '--target', target],
            cwd='../dbt',  # Local development path
            env=env,
            capture_output=True,
            text=True,
            timeout=1800  # 30 minutes timeout
        )
        
        if result.returncode != 0:
            logging.error(f"dbt run failed: {result.stderr}")
            raise Exception(f"dbt run failed: {result.stderr}")
        
        logging.info(f"dbt run successful: {result.stdout}")
        
        # Run dbt tests
        test_result = subprocess.run(
            ['dbt', 'test', '--target', target],
            cwd='../dbt',
            env=env,
            capture_output=True,
            text=True,
            timeout=600  # 10 minutes timeout
        )
        
        if test_result.returncode != 0:
            logging.warning(f"dbt tests failed: {test_result.stderr}")
            context['task_instance'].xcom_push(key='dbt_test_failures', value=test_result.stderr)
        else:
            logging.info(f"dbt tests passed: {test_result.stdout}")
        
        return result.stdout
        
    except subprocess.TimeoutExpired:
        logging.error("dbt run timed out")
        raise Exception("dbt run timed out after 30 minutes")

def update_clickhouse_realtime(**context):
    """Update ClickHouse with real-time data"""
    import requests
    import json
    from airflow.models import Variable
    
    # Get ClickHouse connection details from Airflow Variables or environment
    clickhouse_host = Variable.get("clickhouse_host", default_var=os.getenv('CLICKHOUSE_HOST', 'clickhouse'))
    clickhouse_port = Variable.get("clickhouse_port", default_var=os.getenv('CLICKHOUSE_PORT', '8123'))
    clickhouse_url = f"http://{clickhouse_host}:{clickhouse_port}"
    
    # Get recent data from PostgreSQL
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Extract recent transactions for ClickHouse
    recent_transactions_sql = """
    SELECT 
        transaction_id,
        user_id,
        product_id,
        quantity,
        unit_price,
        total_amount,
        discount_amount,
        tax_amount,
        status,
        payment_method,
        created_at
    FROM transactions 
    WHERE created_at >= NOW() - INTERVAL '1 hour'
      AND status = 'completed'
    """
    
    transactions = postgres_hook.get_records(recent_transactions_sql)
    
    if transactions:
        # Insert into ClickHouse
        insert_sql = """
        INSERT INTO analytics.transactions 
        (transaction_id, user_id, product_id, quantity, unit_price, total_amount, 
         discount_amount, tax_amount, status, payment_method, created_at)
        VALUES
        """
        
        values = []
        for tx in transactions:
            values.append(f"('{tx[0]}', '{tx[1]}', '{tx[2]}', {tx[3]}, {tx[4]}, {tx[5]}, {tx[6]}, {tx[7]}, '{tx[8]}', '{tx[9]}', '{tx[10]}')")
        
        full_sql = insert_sql + ",".join(values)
        
        try:
            # Get ClickHouse credentials from Airflow Variables or environment
            clickhouse_user = Variable.get("clickhouse_user", default_var=os.getenv('CLICKHOUSE_USER', 'analytics_user'))
            clickhouse_password = Variable.get("clickhouse_password", default_var=os.getenv('CLICKHOUSE_PASSWORD', ''))
            
            response = requests.post(
                clickhouse_url,
                data=full_sql,
                auth=(clickhouse_user, clickhouse_password),
                timeout=60
            )
            
            if response.status_code == 200:
                logging.info(f"Successfully inserted {len(transactions)} transactions into ClickHouse")
            else:
                logging.error(f"ClickHouse insert failed: {response.text}")
                raise Exception(f"ClickHouse insert failed: {response.text}")
                
        except requests.RequestException as e:
            logging.error(f"Failed to connect to ClickHouse: {e}")
            raise Exception(f"Failed to connect to ClickHouse: {e}")
    
    else:
        logging.info("No recent transactions to insert into ClickHouse")

def generate_data_quality_report(**context):
    """Generate comprehensive data quality report"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    quality_checks = {
        'user_data_quality': """
            SELECT 
                'users' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN email IS NULL OR email = '' THEN 1 END) as null_emails,
                COUNT(CASE WHEN first_name IS NULL OR first_name = '' THEN 1 END) as null_first_names,
                COUNT(CASE WHEN date_of_birth > CURRENT_DATE THEN 1 END) as future_birth_dates,
                COUNT(CASE WHEN registration_date > CURRENT_TIMESTAMP THEN 1 END) as future_registrations
        """,
        'product_data_quality': """
            SELECT 
                'products' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN name IS NULL OR name = '' THEN 1 END) as null_names,
                COUNT(CASE WHEN price <= 0 THEN 1 END) as invalid_prices,
                COUNT(CASE WHEN cost < 0 THEN 1 END) as negative_costs,
                COUNT(CASE WHEN price < cost THEN 1 END) as negative_margins
        """,
        'transaction_data_quality': """
            SELECT 
                'transactions' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN quantity <= 0 THEN 1 END) as invalid_quantities,
                COUNT(CASE WHEN unit_price <= 0 THEN 1 END) as invalid_prices,
                COUNT(CASE WHEN total_amount <= 0 THEN 1 END) as invalid_totals,
                COUNT(CASE WHEN ABS(total_amount - (unit_price * quantity - discount_amount + tax_amount)) > 0.01 THEN 1 END) as calculation_errors
        """
    }
    
    quality_report = {}
    for check_name, sql in quality_checks.items():
        result = postgres_hook.get_first(sql)
        columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
        quality_report[check_name] = dict(zip(columns, result))
    
    # Calculate quality scores
    for check_name, metrics in quality_report.items():
        total = metrics['total_records']
        issues = sum(v for k, v in metrics.items() if k != 'table_name' and k != 'total_records')
        quality_score = ((total - issues) / total * 100) if total > 0 else 0
        quality_report[check_name]['quality_score'] = round(quality_score, 2)
    
    logging.info(f"Data Quality Report: {quality_report}")
    context['task_instance'].xcom_push(key='quality_report', value=quality_report)
    
    return quality_report

def send_pipeline_notification(**context):
    """Send pipeline completion notification"""
    # Get metrics from previous tasks
    extraction_results = context['task_instance'].xcom_pull(key='extraction_results')
    quality_report = context['task_instance'].xcom_pull(key='quality_report')
    
    # Create summary message
    message = f"""
    Data Pipeline Execution Summary
    ==============================
    
    Execution Time: {context['ds']}
    DAG Run ID: {context['run_id']}
    
    Data Processed:
    - Users: {extraction_results['users']['total_users']}
    - Products: {extraction_results['products']['total_products']}
    - Transactions: {extraction_results['transactions']['total_transactions']}
    - Events: {extraction_results['user_events']['total_events']}
    
    Data Quality Scores:
    - Users: {quality_report['user_data_quality']['quality_score']}%
    - Products: {quality_report['product_data_quality']['quality_score']}%
    - Transactions: {quality_report['transaction_data_quality']['quality_score']}%
    
    Revenue Processed: ${extraction_results['transactions']['total_revenue']:,.2f}
    
    Status: SUCCESS ✅
    """
    
    logging.info(message)
    # In production, this would send to Slack, email, or monitoring system
    return message

# Task definitions
start_task = DummyOperator(
    task_id='start_pipeline',
    dag=dag,
)

# Data freshness check
freshness_check = PythonOperator(
    task_id='check_data_freshness',
    python_callable=check_data_freshness,
    dag=dag,
)

# Data extraction and validation
extract_data = PythonOperator(
    task_id='extract_and_validate_data',
    python_callable=extract_and_validate_data,
    dag=dag,
)

# Processing decision
processing_decision = BranchPythonOperator(
    task_id='decide_processing_path',
    python_callable=decide_processing_path,
    dag=dag,
)

# Processing task group
with TaskGroup('processing', dag=dag) as processing_group:
    
    full_processing = PythonOperator(
        task_id='full_processing',
        python_callable=run_dbt_models,
        dag=dag,
    )
    
    incremental_processing = PythonOperator(
        task_id='incremental_processing',
        python_callable=run_dbt_models,
        dag=dag,
    )
    
    skip_processing = DummyOperator(
        task_id='skip_processing',
        dag=dag,
    )

# Post-processing tasks
update_clickhouse = PythonOperator(
    task_id='update_clickhouse_realtime',
    python_callable=update_clickhouse_realtime,
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

quality_report = PythonOperator(
    task_id='generate_quality_report',
    python_callable=generate_data_quality_report,
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

# Notification
notify_completion = PythonOperator(
    task_id='send_notification',
    python_callable=send_pipeline_notification,
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_pipeline',
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

# Task dependencies
start_task >> freshness_check >> extract_data >> processing_decision
processing_decision >> processing_group
processing_group >> [update_clickhouse, quality_report]
[update_clickhouse, quality_report] >> notify_completion >> end_task