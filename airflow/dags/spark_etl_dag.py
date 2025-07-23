"""
Airflow DAG for Spark ETL processing
Orchestrates the data pipeline from Kafka -> S3 -> Spark -> Snowflake
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import KubernetesPodOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.sensors.s3_key_sensor import S3KeySensor
from airflow.utils.dates import days_ago

# Default arguments
default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': days_ago(1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
    'max_active_runs': 1,
}

# DAG definition
dag = DAG(
    'spark_etl_pipeline',
    default_args=default_args,
    description='Spark ETL pipeline for processing Kafka data',
    schedule_interval='@hourly',  # Run every hour
    catchup=False,
    tags=['spark', 'etl', 'kafka', 'data-pipeline'],
)

# Check if new data is available in S3 (from Kafka Connect)
check_s3_data = S3KeySensor(
    task_id='check_s3_data_available',
    bucket_name='{{ var.value.s3_bucket_raw }}',
    bucket_key='kafka-data/transactions/',
    wildcard_match=True,
    timeout=300,
    poke_interval=60,
    dag=dag,
)

# Spark ETL Job
spark_etl_job = KubernetesPodOperator(
    task_id='spark_etl_processing',
    name='spark-etl-job',
    namespace='data-pipeline',
    image='data-pipeline/spark-jobs:latest',
    cmds=['python'],
    arguments=['/app/jobs/etl_job.py'],
    env_vars={
        'S3_BUCKET_RAW': '{{ var.value.s3_bucket_raw }}',
        'S3_BUCKET_PROCESSED': '{{ var.value.s3_bucket_processed }}',
        'SPARK_MASTER_URL': 'k8s://https://kubernetes.default.svc:443',
    },
    secrets=[
        {
            'deploy_type': 'env',
            'deploy_target': 'AWS_ACCESS_KEY_ID',
            'secret': 'aws-credentials',
            'key': 'access-key-id',
        },
        {
            'deploy_type': 'env',
            'deploy_target': 'AWS_SECRET_ACCESS_KEY',
            'secret': 'aws-credentials',
            'key': 'secret-access-key',
        },
    ],
    container_resources={
        'requests': {
            'memory': '2Gi',
            'cpu': '1000m'
        },
        'limits': {
            'memory': '4Gi',
            'cpu': '2000m'
        }
    },
    is_delete_operator_pod=True,
    get_logs=True,
    dag=dag,
)

# Data Quality Checks
data_quality_job = KubernetesPodOperator(
    task_id='data_quality_checks',
    name='data-quality-job',
    namespace='data-pipeline',
    image='data-pipeline/spark-jobs:latest',
    cmds=['python'],
    arguments=['/app/jobs/data_quality_job.py'],
    env_vars={
        'S3_BUCKET_PROCESSED': '{{ var.value.s3_bucket_processed }}',
    },
    secrets=[
        {
            'deploy_type': 'env',
            'deploy_target': 'AWS_ACCESS_KEY_ID',
            'secret': 'aws-credentials',
            'key': 'access-key-id',
        },
        {
            'deploy_type': 'env',
            'deploy_target': 'AWS_SECRET_ACCESS_KEY',
            'secret': 'aws-credentials',
            'key': 'secret-access-key',
        },
    ],
    container_resources={
        'requests': {
            'memory': '1Gi',
            'cpu': '500m'
        },
        'limits': {
            'memory': '2Gi',
            'cpu': '1000m'
        }
    },
    is_delete_operator_pod=True,
    get_logs=True,
    dag=dag,
)

# Trigger dbt transformations (placeholder for now)
def trigger_dbt_run():
    """Trigger dbt transformations in Snowflake"""
    # This will be implemented when dbt is fully integrated
    print("dbt transformations would be triggered here")
    return "dbt_run_completed"

dbt_transformations = PythonOperator(
    task_id='dbt_transformations',
    python_callable=trigger_dbt_run,
    dag=dag,
)

# Load data to Snowflake (placeholder for now)
def load_to_snowflake():
    """Load processed data to Snowflake"""
    # This will be implemented when Snowflake is configured
    print("Data would be loaded to Snowflake here")
    return "snowflake_load_completed"

snowflake_load = PythonOperator(
    task_id='load_to_snowflake',
    python_callable=load_to_snowflake,
    dag=dag,
)

# Update pipeline metadata
def update_pipeline_metadata():
    """Update pipeline run metadata in PostgreSQL"""
    pg_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Insert pipeline run record
    sql = """
    INSERT INTO pipeline_runs (
        dag_id, 
        run_id, 
        start_time, 
        status
    ) VALUES (
        %s, %s, %s, %s
    )
    """
    
    pg_hook.run(sql, parameters=[
        dag.dag_id,
        '{{ run_id }}',
        '{{ ts }}',
        'completed'
    ])

update_metadata = PythonOperator(
    task_id='update_pipeline_metadata',
    python_callable=update_pipeline_metadata,
    dag=dag,
)

# Define task dependencies
check_s3_data >> spark_etl_job >> data_quality_job >> dbt_transformations >> snowflake_load >> update_metadata

# Additional monitoring task (runs in parallel)
monitor_spark_job = BashOperator(
    task_id='monitor_spark_resources',
    bash_command="""
    echo "Monitoring Spark job resources..."
    kubectl get pods -n data-pipeline -l app=spark-etl
    kubectl top pods -n data-pipeline -l app=spark-etl || echo "Metrics not available"
    """,
    dag=dag,
)

# Monitor runs in parallel with main pipeline
spark_etl_job >> monitor_spark_job