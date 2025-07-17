---
inclusion: fileMatch
fileMatchPattern: '**/dags/*.py'
---

# Airflow DAG Development Standards

## DAG Structure and Organization

### DAG Definition Standards
```python
# Standard DAG structure
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule

# Always use descriptive default_args
default_args = {
    'owner': 'data-engineering-team',  # Use team name, not individual
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'catchup': False,  # Usually False for data pipelines
    'max_active_runs': 1,  # Prevent overlapping runs
}

# Clear, descriptive DAG definition
dag = DAG(
    'data_pipeline_main',  # Use snake_case
    default_args=default_args,
    description='Main data pipeline orchestrating complete ETL process',
    schedule_interval='@hourly',  # Use cron or presets
    tags=['data-pipeline', 'etl', 'production'],  # Helpful for filtering
    doc_md=__doc__,  # Include documentation
)
```

### Task Naming Conventions
- Use descriptive, action-oriented names
- Follow snake_case convention
- Group related tasks with prefixes

```python
# Good task names
extract_user_data = PythonOperator(...)
validate_data_quality = PythonOperator(...)
transform_with_dbt = PythonOperator(...)
load_to_warehouse = PythonOperator(...)

# Task groups for organization
with TaskGroup('data_extraction', dag=dag) as extraction_group:
    extract_users = PythonOperator(...)
    extract_transactions = PythonOperator(...)
    validate_extracts = PythonOperator(...)
```

## Environment Configuration

### Use Environment-Aware Configuration
```python
from environment_config import config

def run_dbt_models(**context):
    """Run dbt transformations with environment-aware configuration"""
    # Get environment-specific configuration
    dbt_config = config.dbt_config
    env_vars = config.get_all_env_vars()
    
    # Log configuration for debugging
    config.log_config(logging)
    
    # Use environment-appropriate settings
    subprocess.run([
        'dbt', 'run', 
        '--target', dbt_config['target']
    ], cwd=dbt_config['project_path'], env=env_vars)
```

### Connection Management
```python
from airflow.models import Variable
from airflow.providers.postgres.hooks.postgres import PostgresHook

def extract_data(**context):
    """Extract data using proper connection management"""
    # Use Airflow connections, not hardcoded values
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Use Variables for configuration, environment variables as fallback
    batch_size = Variable.get("batch_size", default_var=1000)
    
    # Always handle connection errors gracefully
    try:
        result = postgres_hook.get_records(sql)
        logging.info(f"Extracted {len(result)} records")
        return result
    except Exception as e:
        logging.error(f"Data extraction failed: {e}")
        raise
```

## Error Handling and Logging

### Comprehensive Error Handling
```python
def process_data(**context):
    """Process data with proper error handling"""
    try:
        # Main processing logic
        result = perform_data_processing()
        
        # Store results in XCom for downstream tasks
        context['task_instance'].xcom_push(key='processing_results', value=result)
        
        # Log success with metrics
        logging.info(f"Processing completed successfully. Processed {len(result)} records")
        return result
        
    except ValidationError as e:
        # Handle specific error types appropriately
        logging.error(f"Data validation failed: {e}")
        # Push error details to XCom for monitoring
        context['task_instance'].xcom_push(key='validation_errors', value=str(e))
        raise
        
    except DatabaseError as e:
        # Database-specific error handling
        logging.error(f"Database operation failed: {e}")
        # Could implement retry logic here
        raise
        
    except Exception as e:
        # Catch-all for unexpected errors
        logging.error(f"Unexpected error in data processing: {e}")
        # Send alert for investigation
        send_alert(f"Unexpected error in {context['task_instance'].task_id}: {e}")
        raise
```

### Structured Logging
```python
import logging
import json

def log_structured_message(level, message, **kwargs):
    """Log structured messages for better monitoring"""
    log_data = {
        'message': message,
        'timestamp': datetime.utcnow().isoformat(),
        **kwargs
    }
    
    if level == 'info':
        logging.info(json.dumps(log_data))
    elif level == 'error':
        logging.error(json.dumps(log_data))
    elif level == 'warning':
        logging.warning(json.dumps(log_data))

# Usage in tasks
def extract_data(**context):
    log_structured_message('info', 'Starting data extraction', 
                          task_id=context['task_instance'].task_id,
                          dag_id=context['dag'].dag_id,
                          execution_date=str(context['execution_date']))
```

## Data Quality and Monitoring

### Built-in Data Quality Checks
```python
def validate_data_quality(**context):
    """Implement comprehensive data quality validation"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Define quality checks
    quality_checks = {
        'completeness': """
            SELECT 
                COUNT(*) as total_records,
                COUNT(CASE WHEN email IS NULL THEN 1 END) as null_emails,
                COUNT(CASE WHEN user_id IS NULL THEN 1 END) as null_user_ids
            FROM users
        """,
        'uniqueness': """
            SELECT 
                COUNT(*) as total_records,
                COUNT(DISTINCT user_id) as unique_user_ids,
                COUNT(*) - COUNT(DISTINCT user_id) as duplicate_count
            FROM users
        """,
        'validity': """
            SELECT 
                COUNT(CASE WHEN email NOT LIKE '%@%' THEN 1 END) as invalid_emails,
                COUNT(CASE WHEN created_at > CURRENT_TIMESTAMP THEN 1 END) as future_dates
            FROM users
        """
    }
    
    quality_results = {}
    quality_issues = []
    
    for check_name, sql in quality_checks.items():
        result = postgres_hook.get_first(sql)
        quality_results[check_name] = result
        
        # Implement business rules for quality thresholds
        if check_name == 'completeness' and result[1] > 0:  # null_emails
            quality_issues.append(f"Found {result[1]} users with null emails")
        
        if check_name == 'uniqueness' and result[2] > 0:  # duplicate_count
            quality_issues.append(f"Found {result[2]} duplicate user IDs")
    
    # Store results and raise alerts if needed
    context['task_instance'].xcom_push(key='quality_results', value=quality_results)
    
    if quality_issues:
        logging.warning(f"Data quality issues detected: {quality_issues}")
        context['task_instance'].xcom_push(key='quality_issues', value=quality_issues)
        # Could fail the task or send alerts based on severity
    
    return quality_results
```

### SLA Monitoring
```python
def check_sla_compliance(**context):
    """Monitor SLA compliance across pipeline"""
    from airflow.models import DagRun
    
    # Define SLAs
    slas = {
        'pipeline_duration_minutes': 60,
        'data_freshness_hours': 2,
        'success_rate_percent': 95
    }
    
    # Check pipeline duration
    dag_run = context['dag_run']
    if dag_run.end_date and dag_run.start_date:
        duration = (dag_run.end_date - dag_run.start_date).total_seconds() / 60
        if duration > slas['pipeline_duration_minutes']:
            send_sla_alert('Pipeline Duration', duration, slas['pipeline_duration_minutes'])
    
    # Check data freshness
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    freshness_check = """
        SELECT EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 as hours_since_latest
        FROM transactions
    """
    hours_old = postgres_hook.get_first(freshness_check)[0]
    
    if hours_old > slas['data_freshness_hours']:
        send_sla_alert('Data Freshness', hours_old, slas['data_freshness_hours'])
```

## Task Dependencies and Flow Control

### Smart Branching Logic
```python
def decide_processing_path(**context):
    """Intelligent branching based on data conditions"""
    # Get data metrics from upstream task
    extraction_results = context['task_instance'].xcom_pull(key='extraction_results')
    
    # Business logic for processing decisions
    recent_records = extraction_results.get('recent_records', 0)
    total_records = extraction_results.get('total_records', 0)
    
    # Log decision reasoning
    logging.info(f"Decision factors: recent_records={recent_records}, total_records={total_records}")
    
    if recent_records > 10000:  # High volume
        logging.info("Choosing full processing path due to high volume")
        return 'processing.full_processing'
    elif recent_records > 0:    # Normal volume
        logging.info("Choosing incremental processing path")
        return 'processing.incremental_processing'
    else:                       # No new data
        logging.info("Skipping processing - no new data")
        return 'processing.skip_processing'

# Use BranchPythonOperator for conditional logic
processing_decision = BranchPythonOperator(
    task_id='decide_processing_path',
    python_callable=decide_processing_path,
    dag=dag,
)
```

### Trigger Rules for Complex Dependencies
```python
# Task that runs regardless of upstream success/failure
cleanup_task = PythonOperator(
    task_id='cleanup_temp_data',
    python_callable=cleanup_temporary_files,
    trigger_rule=TriggerRule.ALL_DONE,  # Run after all upstream tasks complete
    dag=dag,
)

# Task that runs only if no upstream failures
success_notification = PythonOperator(
    task_id='send_success_notification',
    python_callable=send_success_alert,
    trigger_rule=TriggerRule.ALL_SUCCESS,
    dag=dag,
)

# Task that runs if any upstream task fails
failure_notification = PythonOperator(
    task_id='send_failure_notification',
    python_callable=send_failure_alert,
    trigger_rule=TriggerRule.ONE_FAILED,
    dag=dag,
)
```

## Performance and Resource Management

### Resource-Aware Task Configuration
```python
# Configure resources based on task requirements
heavy_processing_task = PythonOperator(
    task_id='heavy_data_processing',
    python_callable=process_large_dataset,
    pool='heavy_processing_pool',  # Use resource pools
    queue='high_memory_queue',     # Route to appropriate workers
    dag=dag,
)

# Set timeouts for long-running tasks
dbt_transform = BashOperator(
    task_id='run_dbt_transformations',
    bash_command='dbt run --target prod',
    execution_timeout=timedelta(hours=2),  # Prevent hanging
    dag=dag,
)
```

### Parallel Processing Patterns
```python
# Process multiple data sources in parallel
with TaskGroup('parallel_extraction', dag=dag) as extraction_group:
    
    extract_users = PythonOperator(
        task_id='extract_users',
        python_callable=extract_user_data,
    )
    
    extract_products = PythonOperator(
        task_id='extract_products', 
        python_callable=extract_product_data,
    )
    
    extract_transactions = PythonOperator(
        task_id='extract_transactions',
        python_callable=extract_transaction_data,
    )

# Synchronization point after parallel tasks
validate_all_extracts = PythonOperator(
    task_id='validate_all_extracts',
    python_callable=validate_extracted_data,
    dag=dag,
)

# Dependencies
extraction_group >> validate_all_extracts
```

## Testing and Validation

### DAG Testing Patterns
```python
# Include validation functions in DAGs
def validate_dag_structure(**context):
    """Validate DAG structure and dependencies"""
    dag = context['dag']
    
    # Check for common issues
    issues = []
    
    # Ensure all tasks have owners
    for task in dag.tasks:
        if not hasattr(task, 'owner') or not task.owner:
            issues.append(f"Task {task.task_id} missing owner")
    
    # Check for circular dependencies
    try:
        dag.test_cycle()
    except Exception as e:
        issues.append(f"Circular dependency detected: {e}")
    
    if issues:
        raise ValueError(f"DAG validation failed: {issues}")
    
    return "DAG structure validated successfully"

# Include as first task in critical DAGs
validate_dag = PythonOperator(
    task_id='validate_dag_structure',
    python_callable=validate_dag_structure,
    dag=dag,
)
```

## Documentation and Maintenance

### Self-Documenting DAGs
```python
"""
Data Pipeline Main DAG

This DAG orchestrates the complete ETL process for our data pipeline:

1. Data Extraction: Pulls data from PostgreSQL source systems
2. Data Validation: Performs quality checks on extracted data  
3. Data Transformation: Runs dbt models to transform and model data
4. Data Loading: Loads transformed data to Snowflake data warehouse
5. Real-time Updates: Updates ClickHouse for real-time analytics
6. Monitoring: Generates data quality reports and sends notifications

Schedule: Hourly (every hour at minute 0)
Owner: Data Engineering Team
SLA: Must complete within 45 minutes
Dependencies: PostgreSQL, Snowflake, ClickHouse, dbt

For troubleshooting, see: https://wiki.company.com/data-pipeline-runbook
"""

# Use task documentation
extract_data = PythonOperator(
    task_id='extract_source_data',
    python_callable=extract_data_function,
    doc_md="""
    ## Extract Source Data
    
    Extracts data from PostgreSQL source systems including:
    - Users table (incremental based on updated_at)
    - Transactions table (last 24 hours)
    - Product catalog (full refresh daily)
    
    **Monitoring**: Check for data freshness alerts
    **Troubleshooting**: Verify database connectivity and query performance
    """,
    dag=dag,
)
```

## Security Best Practices

### Secure Credential Handling
```python
# Never hardcode credentials
# ❌ Don't do this
# DATABASE_PASSWORD = "secret123"

# ✅ Do this instead
from airflow.models import Variable
from airflow.providers.postgres.hooks.postgres import PostgresHook

def secure_data_access(**context):
    """Access data using secure credential management"""
    
    # Use Airflow Connections for database access
    postgres_hook = PostgresHook(postgres_conn_id='postgres_prod')
    
    # Use Variables for configuration (encrypted in Airflow)
    api_key = Variable.get("external_api_key")
    
    # Use environment variables as fallback
    backup_host = os.getenv('BACKUP_DATABASE_HOST')
    
    # Log access (without sensitive data)
    logging.info(f"Accessing database via connection: postgres_prod")
```

### Audit Logging
```python
def audit_data_access(**context):
    """Log data access for compliance"""
    audit_log = {
        'user': context.get('dag').owner,
        'dag_id': context['dag'].dag_id,
        'task_id': context['task_instance'].task_id,
        'execution_date': str(context['execution_date']),
        'data_accessed': ['users', 'transactions'],
        'purpose': 'ETL processing',
        'timestamp': datetime.utcnow().isoformat()
    }
    
    # Send to audit system
    send_audit_log(audit_log)
```