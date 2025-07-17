"""
Data Backfill DAG - Process historical data in batches
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.dummy import DummyOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule
import pandas as pd
import logging

# Default arguments
default_args = {
    'owner': 'data-engineering-team',
    'depends_on_past': True,  # Important for backfill jobs
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 3,
    'retry_delay': timedelta(minutes=10),
    'catchup': True,  # Enable catchup for backfill
    'max_active_runs': 3,  # Limit concurrent runs
}

# DAG definition
dag = DAG(
    'data_backfill',
    default_args=default_args,
    description='Process historical data in manageable batches',
    schedule_interval='@daily',  # Process one day at a time
    tags=['backfill', 'historical', 'batch-processing'],
    doc_md=__doc__,
)

def validate_backfill_date(**context):
    """Validate that the backfill date is appropriate"""
    execution_date = context['ds']
    current_date = datetime.now().strftime('%Y-%m-%d')
    
    # Don't process future dates
    if execution_date > current_date:
        raise ValueError(f"Cannot backfill future date: {execution_date}")
    
    # Check if data exists for this date
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    check_query = """
    SELECT 
        COUNT(*) as transaction_count,
        COUNT(DISTINCT user_id) as user_count,
        SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as revenue
    FROM transactions 
    WHERE DATE(created_at) = %s
    """
    
    result = postgres_hook.get_first(check_query, parameters=[execution_date])
    transaction_count, user_count, revenue = result
    
    logging.info(f"Date {execution_date}: {transaction_count} transactions, {user_count} users, ${revenue} revenue")
    
    # Store metrics for downstream tasks
    context['task_instance'].xcom_push(key='daily_metrics', value={
        'date': execution_date,
        'transaction_count': transaction_count,
        'user_count': user_count,
        'revenue': float(revenue) if revenue else 0
    })
    
    return {
        'transaction_count': transaction_count,
        'user_count': user_count,
        'revenue': float(revenue) if revenue else 0
    }

def extract_daily_data(**context):
    """Extract data for the specific date"""
    execution_date = context['ds']
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Extract transactions for the date
    transactions_query = """
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
        shipping_address,
        created_at,
        updated_at
    FROM transactions 
    WHERE DATE(created_at) = %s
    ORDER BY created_at
    """
    
    transactions = postgres_hook.get_records(transactions_query, parameters=[execution_date])
    
    # Extract user events for the date
    events_query = """
    SELECT 
        event_id,
        user_id,
        session_id,
        event_type,
        timestamp,
        page_url,
        product_id,
        search_query,
        device_type,
        browser,
        ip_address,
        properties
    FROM user_events 
    WHERE DATE(timestamp) = %s
    ORDER BY timestamp
    """
    
    events = postgres_hook.get_records(events_query, parameters=[execution_date])
    
    logging.info(f"Extracted {len(transactions)} transactions and {len(events)} events for {execution_date}")
    
    # Store extracted data
    context['task_instance'].xcom_push(key='transactions_data', value=len(transactions))
    context['task_instance'].xcom_push(key='events_data', value=len(events))
    
    return {
        'transactions_count': len(transactions),
        'events_count': len(events)
    }

def process_daily_aggregations(**context):
    """Process daily aggregations for the specific date"""
    execution_date = context['ds']
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Create daily aggregation table if not exists
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS daily_aggregations (
        date DATE PRIMARY KEY,
        total_transactions INTEGER,
        successful_transactions INTEGER,
        total_revenue DECIMAL(12,2),
        unique_customers INTEGER,
        unique_products INTEGER,
        avg_order_value DECIMAL(10,2),
        total_events INTEGER,
        unique_sessions INTEGER,
        conversion_rate DECIMAL(5,2),
        processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    """
    
    postgres_hook.run(create_table_sql)
    
    # Calculate daily aggregations
    aggregation_query = """
    WITH transaction_stats AS (
        SELECT 
            DATE(created_at) as date,
            COUNT(*) as total_transactions,
            COUNT(CASE WHEN status = 'completed' THEN 1 END) as successful_transactions,
            SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue,
            COUNT(DISTINCT user_id) as unique_customers,
            COUNT(DISTINCT product_id) as unique_products,
            AVG(CASE WHEN status = 'completed' THEN total_amount END) as avg_order_value
        FROM transactions 
        WHERE DATE(created_at) = %s
        GROUP BY DATE(created_at)
    ),
    event_stats AS (
        SELECT 
            DATE(timestamp) as date,
            COUNT(*) as total_events,
            COUNT(DISTINCT session_id) as unique_sessions
        FROM user_events 
        WHERE DATE(timestamp) = %s
        GROUP BY DATE(timestamp)
    )
    SELECT 
        COALESCE(t.date, e.date) as date,
        COALESCE(t.total_transactions, 0) as total_transactions,
        COALESCE(t.successful_transactions, 0) as successful_transactions,
        COALESCE(t.total_revenue, 0) as total_revenue,
        COALESCE(t.unique_customers, 0) as unique_customers,
        COALESCE(t.unique_products, 0) as unique_products,
        COALESCE(t.avg_order_value, 0) as avg_order_value,
        COALESCE(e.total_events, 0) as total_events,
        COALESCE(e.unique_sessions, 0) as unique_sessions,
        CASE 
            WHEN COALESCE(e.unique_sessions, 0) > 0 
            THEN ROUND(COALESCE(t.successful_transactions, 0)::DECIMAL / e.unique_sessions * 100, 2)
            ELSE 0 
        END as conversion_rate
    FROM transaction_stats t
    FULL OUTER JOIN event_stats e ON t.date = e.date
    """
    
    result = postgres_hook.get_first(aggregation_query, parameters=[execution_date, execution_date])
    
    if result and result[0]:  # If we have data
        # Insert or update daily aggregation
        upsert_sql = """
        INSERT INTO daily_aggregations 
        (date, total_transactions, successful_transactions, total_revenue, 
         unique_customers, unique_products, avg_order_value, total_events, 
         unique_sessions, conversion_rate)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        ON CONFLICT (date) 
        DO UPDATE SET 
            total_transactions = EXCLUDED.total_transactions,
            successful_transactions = EXCLUDED.successful_transactions,
            total_revenue = EXCLUDED.total_revenue,
            unique_customers = EXCLUDED.unique_customers,
            unique_products = EXCLUDED.unique_products,
            avg_order_value = EXCLUDED.avg_order_value,
            total_events = EXCLUDED.total_events,
            unique_sessions = EXCLUDED.unique_sessions,
            conversion_rate = EXCLUDED.conversion_rate,
            processed_at = CURRENT_TIMESTAMP
        """
        
        postgres_hook.run(upsert_sql, parameters=result)
        
        logging.info(f"Processed daily aggregations for {execution_date}: {result}")
        
        # Store aggregation results
        context['task_instance'].xcom_push(key='daily_aggregation', value={
            'date': str(result[0]),
            'total_transactions': result[1],
            'successful_transactions': result[2],
            'total_revenue': float(result[3]),
            'conversion_rate': float(result[9])
        })
        
        return result
    else:
        logging.info(f"No data found for {execution_date}")
        return None

def run_incremental_dbt(**context):
    """Run dbt models incrementally for the specific date"""
    execution_date = context['ds']
    
    import subprocess
    import os
    
    # Set environment variables for dbt
    env = os.environ.copy()
    env.update({
        'POSTGRES_HOST': 'postgres.data-storage.svc.cluster.local',
        'POSTGRES_PORT': '5432',
        'POSTGRES_DB': 'transactions_db',
        'POSTGRES_USER': 'postgres',
        'POSTGRES_PASSWORD': 'postgres_password',
        'DBT_EXECUTION_DATE': execution_date
    })
    
    try:
        # Run dbt with date filter
        result = subprocess.run(
            ['dbt', 'run', '--target', 'dev', '--vars', f'{{"execution_date": "{execution_date}"}}'],
            cwd='/opt/airflow/dbt',
            env=env,
            capture_output=True,
            text=True,
            timeout=1800  # 30 minutes timeout
        )
        
        if result.returncode != 0:
            logging.error(f"dbt run failed for {execution_date}: {result.stderr}")
            raise Exception(f"dbt run failed: {result.stderr}")
        
        logging.info(f"dbt run successful for {execution_date}: {result.stdout}")
        return result.stdout
        
    except subprocess.TimeoutExpired:
        logging.error(f"dbt run timed out for {execution_date}")
        raise Exception("dbt run timed out after 30 minutes")

def validate_processed_data(**context):
    """Validate that the data was processed correctly"""
    execution_date = context['ds']
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Check if aggregations were created
    validation_query = """
    SELECT 
        date,
        total_transactions,
        successful_transactions,
        total_revenue,
        conversion_rate,
        processed_at
    FROM daily_aggregations 
    WHERE date = %s
    """
    
    result = postgres_hook.get_first(validation_query, parameters=[execution_date])
    
    if not result:
        raise ValueError(f"No aggregations found for {execution_date}")
    
    date, total_tx, successful_tx, revenue, conversion_rate, processed_at = result
    
    # Validation checks
    validation_issues = []
    
    if total_tx < 0:
        validation_issues.append("Negative transaction count")
    
    if successful_tx > total_tx:
        validation_issues.append("Successful transactions exceed total transactions")
    
    if revenue < 0:
        validation_issues.append("Negative revenue")
    
    if conversion_rate < 0 or conversion_rate > 100:
        validation_issues.append("Invalid conversion rate")
    
    if validation_issues:
        logging.error(f"Validation failed for {execution_date}: {validation_issues}")
        raise ValueError(f"Data validation failed: {validation_issues}")
    
    logging.info(f"Data validation passed for {execution_date}")
    
    # Store validation results
    context['task_instance'].xcom_push(key='validation_results', value={
        'date': str(date),
        'total_transactions': total_tx,
        'successful_transactions': successful_tx,
        'total_revenue': float(revenue),
        'conversion_rate': float(conversion_rate),
        'validation_passed': True
    })
    
    return result

def update_backfill_progress(**context):
    """Update backfill progress tracking"""
    execution_date = context['ds']
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Create progress tracking table if not exists
    create_progress_table = """
    CREATE TABLE IF NOT EXISTS backfill_progress (
        date DATE PRIMARY KEY,
        status VARCHAR(20),
        transactions_processed INTEGER,
        events_processed INTEGER,
        revenue_processed DECIMAL(12,2),
        started_at TIMESTAMP,
        completed_at TIMESTAMP,
        dag_run_id VARCHAR(255)
    )
    """
    
    postgres_hook.run(create_progress_table)
    
    # Get processing results
    daily_metrics = context['task_instance'].xcom_pull(key='daily_metrics')
    validation_results = context['task_instance'].xcom_pull(key='validation_results')
    
    # Update progress
    upsert_progress = """
    INSERT INTO backfill_progress 
    (date, status, transactions_processed, events_processed, revenue_processed, 
     started_at, completed_at, dag_run_id)
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (date) 
    DO UPDATE SET 
        status = EXCLUDED.status,
        transactions_processed = EXCLUDED.transactions_processed,
        events_processed = EXCLUDED.events_processed,
        revenue_processed = EXCLUDED.revenue_processed,
        completed_at = EXCLUDED.completed_at
    """
    
    postgres_hook.run(upsert_progress, parameters=[
        execution_date,
        'completed',
        daily_metrics.get('transaction_count', 0),
        0,  # events count would come from extract task
        daily_metrics.get('revenue', 0),
        context['dag_run'].start_date,
        datetime.now(),
        context['run_id']
    ])
    
    logging.info(f"Updated backfill progress for {execution_date}")
    
    return f"Backfill completed for {execution_date}"

# Task definitions
start_task = DummyOperator(
    task_id='start_backfill',
    dag=dag,
)

validate_date = PythonOperator(
    task_id='validate_backfill_date',
    python_callable=validate_backfill_date,
    dag=dag,
)

# Data processing task group
with TaskGroup('data_processing', dag=dag) as processing_group:
    
    extract_data = PythonOperator(
        task_id='extract_daily_data',
        python_callable=extract_daily_data,
        dag=dag,
    )
    
    process_aggregations = PythonOperator(
        task_id='process_daily_aggregations',
        python_callable=process_daily_aggregations,
        dag=dag,
    )
    
    run_dbt = PythonOperator(
        task_id='run_incremental_dbt',
        python_callable=run_incremental_dbt,
        dag=dag,
    )

# Validation and completion
validate_data = PythonOperator(
    task_id='validate_processed_data',
    python_callable=validate_processed_data,
    dag=dag,
)

update_progress = PythonOperator(
    task_id='update_backfill_progress',
    python_callable=update_backfill_progress,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_backfill',
    dag=dag,
)

# Task dependencies
start_task >> validate_date >> processing_group >> validate_data >> update_progress >> end_task

# Within processing group
extract_data >> process_aggregations >> run_dbt