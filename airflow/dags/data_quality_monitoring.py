"""
Data Quality Monitoring DAG - Comprehensive data validation and monitoring
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
import json

# Default arguments
default_args = {
    'owner': 'data-quality-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=2),
    'catchup': False,
}

# DAG definition
dag = DAG(
    'data_quality_monitoring',
    default_args=default_args,
    description='Comprehensive data quality monitoring and validation',
    schedule_interval='0 */6 * * *',  # Every 6 hours
    tags=['data-quality', 'monitoring', 'validation'],
    doc_md=__doc__,
)

def run_data_profiling(**context):
    """Profile data to understand distributions and patterns"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    profiling_queries = {
        'user_profile': """
            SELECT 
                'users' as table_name,
                COUNT(*) as total_records,
                COUNT(DISTINCT user_id) as unique_users,
                COUNT(DISTINCT email) as unique_emails,
                COUNT(DISTINCT country) as unique_countries,
                MIN(registration_date) as earliest_registration,
                MAX(registration_date) as latest_registration,
                AVG(EXTRACT(YEAR FROM AGE(CURRENT_DATE, date_of_birth))) as avg_age,
                COUNT(CASE WHEN tier = 'bronze' THEN 1 END) as bronze_users,
                COUNT(CASE WHEN tier = 'silver' THEN 1 END) as silver_users,
                COUNT(CASE WHEN tier = 'gold' THEN 1 END) as gold_users,
                COUNT(CASE WHEN tier = 'platinum' THEN 1 END) as platinum_users,
                COUNT(CASE WHEN is_active THEN 1 END) as active_users
        """,
        'product_profile': """
            SELECT 
                'products' as table_name,
                COUNT(*) as total_records,
                COUNT(DISTINCT product_id) as unique_products,
                COUNT(DISTINCT category) as unique_categories,
                COUNT(DISTINCT brand) as unique_brands,
                MIN(price) as min_price,
                MAX(price) as max_price,
                AVG(price) as avg_price,
                PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price) as median_price,
                COUNT(CASE WHEN is_active THEN 1 END) as active_products,
                AVG(price - cost) as avg_margin
        """,
        'transaction_profile': """
            SELECT 
                'transactions' as table_name,
                COUNT(*) as total_records,
                COUNT(DISTINCT transaction_id) as unique_transactions,
                COUNT(DISTINCT user_id) as unique_customers,
                COUNT(DISTINCT product_id) as unique_products_sold,
                MIN(created_at) as earliest_transaction,
                MAX(created_at) as latest_transaction,
                SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as total_revenue,
                AVG(CASE WHEN status = 'completed' THEN total_amount END) as avg_order_value,
                COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_transactions,
                COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_transactions,
                COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_transactions
        """
    }
    
    profile_results = {}
    for profile_name, query in profiling_queries.items():
        result = postgres_hook.get_first(query)
        columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
        profile_results[profile_name] = dict(zip(columns, result))
        logging.info(f"{profile_name}: {profile_results[profile_name]}")
    
    context['task_instance'].xcom_push(key='profile_results', value=profile_results)
    return profile_results

def check_data_completeness(**context):
    """Check for missing or incomplete data"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    completeness_checks = {
        'user_completeness': """
            SELECT 
                'users' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN user_id IS NULL THEN 1 END) as missing_user_id,
                COUNT(CASE WHEN email IS NULL OR email = '' THEN 1 END) as missing_email,
                COUNT(CASE WHEN first_name IS NULL OR first_name = '' THEN 1 END) as missing_first_name,
                COUNT(CASE WHEN last_name IS NULL OR last_name = '' THEN 1 END) as missing_last_name,
                COUNT(CASE WHEN date_of_birth IS NULL THEN 1 END) as missing_birth_date,
                COUNT(CASE WHEN registration_date IS NULL THEN 1 END) as missing_registration_date,
                COUNT(CASE WHEN country IS NULL OR country = '' THEN 1 END) as missing_country,
                COUNT(CASE WHEN tier IS NULL OR tier = '' THEN 1 END) as missing_tier
        """,
        'product_completeness': """
            SELECT 
                'products' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN product_id IS NULL THEN 1 END) as missing_product_id,
                COUNT(CASE WHEN name IS NULL OR name = '' THEN 1 END) as missing_name,
                COUNT(CASE WHEN category IS NULL OR category = '' THEN 1 END) as missing_category,
                COUNT(CASE WHEN price IS NULL THEN 1 END) as missing_price,
                COUNT(CASE WHEN cost IS NULL THEN 1 END) as missing_cost,
                COUNT(CASE WHEN brand IS NULL OR brand = '' THEN 1 END) as missing_brand,
                COUNT(CASE WHEN description IS NULL OR description = '' THEN 1 END) as missing_description
        """,
        'transaction_completeness': """
            SELECT 
                'transactions' as table_name,
                COUNT(*) as total_records,
                COUNT(CASE WHEN transaction_id IS NULL THEN 1 END) as missing_transaction_id,
                COUNT(CASE WHEN user_id IS NULL THEN 1 END) as missing_user_id,
                COUNT(CASE WHEN product_id IS NULL THEN 1 END) as missing_product_id,
                COUNT(CASE WHEN quantity IS NULL THEN 1 END) as missing_quantity,
                COUNT(CASE WHEN unit_price IS NULL THEN 1 END) as missing_unit_price,
                COUNT(CASE WHEN total_amount IS NULL THEN 1 END) as missing_total_amount,
                COUNT(CASE WHEN status IS NULL OR status = '' THEN 1 END) as missing_status,
                COUNT(CASE WHEN created_at IS NULL THEN 1 END) as missing_created_at
        """
    }
    
    completeness_results = {}
    issues_found = []
    
    for check_name, query in completeness_checks.items():
        result = postgres_hook.get_first(query)
        columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
        completeness_results[check_name] = dict(zip(columns, result))
        
        # Check for issues
        total_records = completeness_results[check_name]['total_records']
        for field, count in completeness_results[check_name].items():
            if field not in ['table_name', 'total_records'] and count > 0:
                percentage = (count / total_records) * 100
                if percentage > 5:  # More than 5% missing is concerning
                    issues_found.append(f"{check_name}: {field} missing in {count} records ({percentage:.1f}%)")
    
    if issues_found:
        logging.warning(f"Data completeness issues found: {issues_found}")
        context['task_instance'].xcom_push(key='completeness_issues', value=issues_found)
    
    context['task_instance'].xcom_push(key='completeness_results', value=completeness_results)
    return completeness_results

def check_data_consistency(**context):
    """Check for data consistency and referential integrity"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    consistency_checks = {
        'referential_integrity': """
            SELECT 
                'referential_integrity' as check_type,
                (SELECT COUNT(*) FROM transactions t 
                 LEFT JOIN users u ON t.user_id = u.user_id 
                 WHERE u.user_id IS NULL) as orphaned_transactions_users,
                (SELECT COUNT(*) FROM transactions t 
                 LEFT JOIN products p ON t.product_id = p.product_id 
                 WHERE p.product_id IS NULL) as orphaned_transactions_products,
                (SELECT COUNT(*) FROM user_events e 
                 LEFT JOIN users u ON e.user_id = u.user_id 
                 WHERE u.user_id IS NULL) as orphaned_events_users
        """,
        'business_logic_consistency': """
            SELECT 
                'business_logic' as check_type,
                COUNT(CASE WHEN quantity <= 0 THEN 1 END) as invalid_quantities,
                COUNT(CASE WHEN unit_price <= 0 THEN 1 END) as invalid_unit_prices,
                COUNT(CASE WHEN total_amount <= 0 AND status = 'completed' THEN 1 END) as invalid_completed_amounts,
                COUNT(CASE WHEN discount_amount < 0 THEN 1 END) as negative_discounts,
                COUNT(CASE WHEN tax_amount < 0 THEN 1 END) as negative_taxes,
                COUNT(CASE WHEN ABS(total_amount - (unit_price * quantity - discount_amount + tax_amount)) > 0.01 THEN 1 END) as calculation_errors
            FROM transactions
        """,
        'temporal_consistency': """
            SELECT 
                'temporal_consistency' as check_type,
                COUNT(CASE WHEN date_of_birth > CURRENT_DATE THEN 1 END) as future_birth_dates,
                COUNT(CASE WHEN registration_date > CURRENT_TIMESTAMP THEN 1 END) as future_registrations,
                COUNT(CASE WHEN last_login < registration_date THEN 1 END) as login_before_registration
            FROM users
        """
    }
    
    consistency_results = {}
    critical_issues = []
    
    for check_name, query in consistency_checks.items():
        result = postgres_hook.get_first(query)
        columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
        consistency_results[check_name] = dict(zip(columns, result))
        
        # Check for critical issues
        for field, count in consistency_results[check_name].items():
            if field != 'check_type' and count > 0:
                if 'orphaned' in field or 'invalid' in field or 'negative' in field or 'future' in field:
                    critical_issues.append(f"{check_name}: {field} = {count}")
    
    if critical_issues:
        logging.error(f"Critical data consistency issues found: {critical_issues}")
        context['task_instance'].xcom_push(key='critical_issues', value=critical_issues)
    
    context['task_instance'].xcom_push(key='consistency_results', value=consistency_results)
    return consistency_results

def check_data_freshness(**context):
    """Check data freshness and timeliness"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    freshness_checks = {
        'transaction_freshness': """
            SELECT 
                'transactions' as table_name,
                MAX(created_at) as latest_record,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 hour' THEN 1 END) as records_last_hour,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 day' THEN 1 END) as records_last_day,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 week' THEN 1 END) as records_last_week,
                EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/3600 as hours_since_latest
        """,
        'event_freshness': """
            SELECT 
                'user_events' as table_name,
                MAX(timestamp) as latest_record,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '1 hour' THEN 1 END) as records_last_hour,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '1 day' THEN 1 END) as records_last_day,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '1 week' THEN 1 END) as records_last_week,
                EXTRACT(EPOCH FROM (NOW() - MAX(timestamp)))/3600 as hours_since_latest
        """,
        'user_activity_freshness': """
            SELECT 
                'user_activity' as table_name,
                MAX(last_login) as latest_login,
                COUNT(CASE WHEN last_login >= NOW() - INTERVAL '1 day' THEN 1 END) as active_users_last_day,
                COUNT(CASE WHEN last_login >= NOW() - INTERVAL '1 week' THEN 1 END) as active_users_last_week,
                COUNT(CASE WHEN last_login >= NOW() - INTERVAL '1 month' THEN 1 END) as active_users_last_month,
                EXTRACT(EPOCH FROM (NOW() - MAX(last_login)))/3600 as hours_since_latest_login
            FROM users WHERE last_login IS NOT NULL
        """
    }
    
    freshness_results = {}
    freshness_alerts = []
    
    for check_name, query in freshness_checks.items():
        result = postgres_hook.get_first(query)
        columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
        freshness_results[check_name] = dict(zip(columns, result))
        
        # Check for freshness issues
        hours_since_latest = freshness_results[check_name].get('hours_since_latest', 0)
        if hours_since_latest and hours_since_latest > 2:  # More than 2 hours old
            freshness_alerts.append(f"{check_name}: Data is {hours_since_latest:.1f} hours old")
    
    if freshness_alerts:
        logging.warning(f"Data freshness alerts: {freshness_alerts}")
        context['task_instance'].xcom_push(key='freshness_alerts', value=freshness_alerts)
    
    context['task_instance'].xcom_push(key='freshness_results', value=freshness_results)
    return freshness_results

def run_statistical_anomaly_detection(**context):
    """Detect statistical anomalies in key metrics"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get daily metrics for the last 30 days
    daily_metrics_query = """
    WITH daily_stats AS (
        SELECT 
            DATE(created_at) as date,
            COUNT(*) as transaction_count,
            SUM(CASE WHEN status = 'completed' THEN total_amount ELSE 0 END) as daily_revenue,
            AVG(CASE WHEN status = 'completed' THEN total_amount END) as avg_order_value,
            COUNT(DISTINCT user_id) as unique_customers,
            COUNT(CASE WHEN status = 'completed' THEN 1 END) as successful_transactions,
            COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_transactions
        FROM transactions 
        WHERE created_at >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY DATE(created_at)
        ORDER BY date
    )
    SELECT 
        date,
        transaction_count,
        daily_revenue,
        avg_order_value,
        unique_customers,
        successful_transactions,
        failed_transactions,
        -- Calculate z-scores for anomaly detection
        ABS(transaction_count - AVG(transaction_count) OVER()) / NULLIF(STDDEV(transaction_count) OVER(), 0) as transaction_count_zscore,
        ABS(daily_revenue - AVG(daily_revenue) OVER()) / NULLIF(STDDEV(daily_revenue) OVER(), 0) as daily_revenue_zscore,
        ABS(unique_customers - AVG(unique_customers) OVER()) / NULLIF(STDDEV(unique_customers) OVER(), 0) as unique_customers_zscore
    FROM daily_stats
    """
    
    results = postgres_hook.get_records(daily_metrics_query)
    columns = [desc[0] for desc in postgres_hook.get_conn().cursor().description]
    
    anomalies = []
    for row in results:
        record = dict(zip(columns, row))
        
        # Check for anomalies (z-score > 2 is considered anomalous)
        if record['transaction_count_zscore'] and record['transaction_count_zscore'] > 2:
            anomalies.append(f"Transaction count anomaly on {record['date']}: {record['transaction_count']} (z-score: {record['transaction_count_zscore']:.2f})")
        
        if record['daily_revenue_zscore'] and record['daily_revenue_zscore'] > 2:
            anomalies.append(f"Revenue anomaly on {record['date']}: ${record['daily_revenue']:.2f} (z-score: {record['daily_revenue_zscore']:.2f})")
        
        if record['unique_customers_zscore'] and record['unique_customers_zscore'] > 2:
            anomalies.append(f"Customer count anomaly on {record['date']}: {record['unique_customers']} (z-score: {record['unique_customers_zscore']:.2f})")
    
    if anomalies:
        logging.warning(f"Statistical anomalies detected: {anomalies}")
        context['task_instance'].xcom_push(key='statistical_anomalies', value=anomalies)
    
    context['task_instance'].xcom_push(key='daily_metrics', value=[dict(zip(columns, row)) for row in results])
    return anomalies

def generate_quality_dashboard(**context):
    """Generate comprehensive data quality dashboard"""
    # Collect all results from previous tasks
    profile_results = context['task_instance'].xcom_pull(key='profile_results')
    completeness_results = context['task_instance'].xcom_pull(key='completeness_results')
    consistency_results = context['task_instance'].xcom_pull(key='consistency_results')
    freshness_results = context['task_instance'].xcom_pull(key='freshness_results')
    
    # Get any issues
    completeness_issues = context['task_instance'].xcom_pull(key='completeness_issues') or []
    critical_issues = context['task_instance'].xcom_pull(key='critical_issues') or []
    freshness_alerts = context['task_instance'].xcom_pull(key='freshness_alerts') or []
    statistical_anomalies = context['task_instance'].xcom_pull(key='statistical_anomalies') or []
    
    # Calculate overall quality score
    total_issues = len(completeness_issues) + len(critical_issues) + len(freshness_alerts) + len(statistical_anomalies)
    quality_score = max(0, 100 - (total_issues * 5))  # Deduct 5 points per issue
    
    dashboard = {
        'execution_date': context['ds'],
        'overall_quality_score': quality_score,
        'data_profile': profile_results,
        'completeness_check': completeness_results,
        'consistency_check': consistency_results,
        'freshness_check': freshness_results,
        'issues_summary': {
            'completeness_issues': completeness_issues,
            'critical_issues': critical_issues,
            'freshness_alerts': freshness_alerts,
            'statistical_anomalies': statistical_anomalies,
            'total_issues': total_issues
        },
        'recommendations': []
    }
    
    # Generate recommendations based on issues
    if completeness_issues:
        dashboard['recommendations'].append("Review data ingestion processes for missing fields")
    if critical_issues:
        dashboard['recommendations'].append("Investigate data validation rules and business logic")
    if freshness_alerts:
        dashboard['recommendations'].append("Check data pipeline scheduling and source system health")
    if statistical_anomalies:
        dashboard['recommendations'].append("Investigate unusual patterns in business metrics")
    
    if not dashboard['recommendations']:
        dashboard['recommendations'].append("Data quality looks good! Continue monitoring.")
    
    logging.info(f"Data Quality Dashboard: Overall Score = {quality_score}%")
    logging.info(f"Total Issues Found: {total_issues}")
    
    context['task_instance'].xcom_push(key='quality_dashboard', value=dashboard)
    return dashboard

def send_quality_alert(**context):
    """Send alerts if critical quality issues are found"""
    dashboard = context['task_instance'].xcom_pull(key='quality_dashboard')
    
    quality_score = dashboard['overall_quality_score']
    total_issues = dashboard['issues_summary']['total_issues']
    
    if quality_score < 80 or total_issues > 5:
        alert_message = f"""
        🚨 DATA QUALITY ALERT 🚨
        
        Overall Quality Score: {quality_score}%
        Total Issues Found: {total_issues}
        
        Critical Issues:
        {chr(10).join(dashboard['issues_summary']['critical_issues'])}
        
        Recommendations:
        {chr(10).join(dashboard['recommendations'])}
        
        Please investigate immediately!
        """
        
        logging.error(alert_message)
        # In production, send to Slack, PagerDuty, etc.
        
    else:
        success_message = f"""
        ✅ Data Quality Check Passed
        
        Overall Quality Score: {quality_score}%
        Total Issues: {total_issues}
        
        All systems operating normally.
        """
        
        logging.info(success_message)
    
    return dashboard

# Task definitions
start_task = DummyOperator(
    task_id='start_quality_monitoring',
    dag=dag,
)

# Data profiling task group
with TaskGroup('data_profiling', dag=dag) as profiling_group:
    
    profile_data = PythonOperator(
        task_id='run_data_profiling',
        python_callable=run_data_profiling,
        dag=dag,
    )

# Data validation task group
with TaskGroup('data_validation', dag=dag) as validation_group:
    
    completeness_check = PythonOperator(
        task_id='check_completeness',
        python_callable=check_data_completeness,
        dag=dag,
    )
    
    consistency_check = PythonOperator(
        task_id='check_consistency',
        python_callable=check_data_consistency,
        dag=dag,
    )
    
    freshness_check = PythonOperator(
        task_id='check_freshness',
        python_callable=check_data_freshness,
        dag=dag,
    )
    
    anomaly_detection = PythonOperator(
        task_id='detect_anomalies',
        python_callable=run_statistical_anomaly_detection,
        dag=dag,
    )

# Reporting tasks
generate_dashboard = PythonOperator(
    task_id='generate_quality_dashboard',
    python_callable=generate_quality_dashboard,
    dag=dag,
)

send_alerts = PythonOperator(
    task_id='send_quality_alerts',
    python_callable=send_quality_alert,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_quality_monitoring',
    dag=dag,
)

# Task dependencies
start_task >> profiling_group >> validation_group >> generate_dashboard >> send_alerts >> end_task