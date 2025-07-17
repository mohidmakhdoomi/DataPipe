"""
Pipeline Monitoring DAG - Monitor all aspects of the data pipeline
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.dummy import DummyOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule
from airflow.models import DagRun, TaskInstance
from airflow.utils.state import State
import requests
import logging
import json

# Default arguments
default_args = {
    'owner': 'monitoring-team',
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
    'pipeline_monitoring',
    default_args=default_args,
    description='Comprehensive monitoring of the entire data pipeline',
    schedule_interval='*/15 * * * *',  # Every 15 minutes
    tags=['monitoring', 'alerting', 'health-check'],
    doc_md=__doc__,
)

def monitor_dag_performance(**context):
    """Monitor performance of all DAGs in the pipeline"""
    from airflow.models import DagModel
    from sqlalchemy import create_engine
    from airflow.configuration import conf
    
    # Get Airflow database connection
    sql_alchemy_conn = conf.get('database', 'sql_alchemy_conn')
    engine = create_engine(sql_alchemy_conn)
    
    # Monitor key DAGs
    key_dags = [
        'data_pipeline_main',
        'data_quality_monitoring', 
        'data_backfill',
        'maintenance_operations'
    ]
    
    dag_performance = {}
    
    for dag_id in key_dags:
        # Get recent DAG runs
        query = f"""
        SELECT 
            dag_id,
            state,
            start_date,
            end_date,
            EXTRACT(EPOCH FROM (end_date - start_date)) as duration_seconds
        FROM dag_run 
        WHERE dag_id = '{dag_id}'
          AND start_date >= NOW() - INTERVAL '24 hours'
        ORDER BY start_date DESC
        LIMIT 10
        """
        
        with engine.connect() as conn:
            result = conn.execute(query)
            runs = result.fetchall()
        
        if runs:
            successful_runs = [r for r in runs if r[1] == 'success']
            failed_runs = [r for r in runs if r[1] == 'failed']
            running_runs = [r for r in runs if r[1] == 'running']
            
            avg_duration = sum(r[4] for r in successful_runs if r[4]) / len(successful_runs) if successful_runs else 0
            
            dag_performance[dag_id] = {
                'total_runs': len(runs),
                'successful_runs': len(successful_runs),
                'failed_runs': len(failed_runs),
                'running_runs': len(running_runs),
                'success_rate': (len(successful_runs) / len(runs)) * 100 if runs else 0,
                'avg_duration_minutes': avg_duration / 60 if avg_duration else 0,
                'last_run_state': runs[0][1] if runs else 'unknown',
                'last_run_start': str(runs[0][2]) if runs else None
            }
        else:
            dag_performance[dag_id] = {
                'total_runs': 0,
                'successful_runs': 0,
                'failed_runs': 0,
                'running_runs': 0,
                'success_rate': 0,
                'avg_duration_minutes': 0,
                'last_run_state': 'no_runs',
                'last_run_start': None
            }
        
        logging.info(f"DAG {dag_id}: {dag_performance[dag_id]}")
    
    context['task_instance'].xcom_push(key='dag_performance', value=dag_performance)
    return dag_performance

def monitor_data_freshness(**context):
    """Monitor data freshness across all sources"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    freshness_checks = {
        'transactions': """
            SELECT 
                'transactions' as source,
                COUNT(*) as total_records,
                MAX(created_at) as latest_record,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '1 hour' THEN 1 END) as records_last_hour,
                COUNT(CASE WHEN created_at >= NOW() - INTERVAL '24 hours' THEN 1 END) as records_last_24h,
                EXTRACT(EPOCH FROM (NOW() - MAX(created_at)))/60 as minutes_since_latest
        """,
        'user_events': """
            SELECT 
                'user_events' as source,
                COUNT(*) as total_records,
                MAX(timestamp) as latest_record,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '1 hour' THEN 1 END) as records_last_hour,
                COUNT(CASE WHEN timestamp >= NOW() - INTERVAL '24 hours' THEN 1 END) as records_last_24h,
                EXTRACT(EPOCH FROM (NOW() - MAX(timestamp)))/60 as minutes_since_latest
        """,
        'users': """
            SELECT 
                'users' as source,
                COUNT(*) as total_records,
                MAX(COALESCE(updated_at, created_at)) as latest_record,
                COUNT(CASE WHEN COALESCE(updated_at, created_at) >= NOW() - INTERVAL '1 hour' THEN 1 END) as records_last_hour,
                COUNT(CASE WHEN COALESCE(updated_at, created_at) >= NOW() - INTERVAL '24 hours' THEN 1 END) as records_last_24h,
                EXTRACT(EPOCH FROM (NOW() - MAX(COALESCE(updated_at, created_at))))/60 as minutes_since_latest
        """
    }
    
    freshness_results = {}
    freshness_alerts = []
    
    for source, query in freshness_checks.items():
        try:
            result = postgres_hook.get_first(query)
            source_name, total_records, latest_record, records_last_hour, records_last_24h, minutes_since_latest = result
            
            freshness_results[source] = {
                'total_records': total_records,
                'latest_record': str(latest_record) if latest_record else None,
                'records_last_hour': records_last_hour,
                'records_last_24h': records_last_24h,
                'minutes_since_latest': float(minutes_since_latest) if minutes_since_latest else None,
                'is_fresh': minutes_since_latest < 60 if minutes_since_latest else False  # Fresh if < 1 hour
            }
            
            # Check for freshness issues
            if minutes_since_latest and minutes_since_latest > 120:  # More than 2 hours
                freshness_alerts.append(f"{source}: Data is {minutes_since_latest:.0f} minutes old")
            
            if records_last_hour == 0 and source in ['transactions', 'user_events']:
                freshness_alerts.append(f"{source}: No new records in the last hour")
                
        except Exception as e:
            logging.error(f"Error checking freshness for {source}: {e}")
            freshness_results[source] = {'error': str(e)}
    
    if freshness_alerts:
        logging.warning(f"Data freshness alerts: {freshness_alerts}")
        context['task_instance'].xcom_push(key='freshness_alerts', value=freshness_alerts)
    
    context['task_instance'].xcom_push(key='freshness_results', value=freshness_results)
    return freshness_results

def monitor_system_resources(**context):
    """Monitor system resources and performance"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Database performance metrics
    db_metrics_query = """
    SELECT 
        'database_performance' as metric_type,
        (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'active') as active_connections,
        (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle') as idle_connections,
        (SELECT COUNT(*) FROM pg_stat_activity WHERE state = 'idle in transaction') as idle_in_transaction,
        (SELECT COUNT(*) FROM pg_stat_activity WHERE query_start < NOW() - INTERVAL '5 minutes' AND state = 'active') as long_running_queries
    """
    
    db_metrics = postgres_hook.get_first(db_metrics_query)
    metric_type, active_conn, idle_conn, idle_in_tx, long_queries = db_metrics
    
    system_metrics = {
        'database': {
            'active_connections': active_conn,
            'idle_connections': idle_conn,
            'idle_in_transaction': idle_in_tx,
            'long_running_queries': long_queries,
            'total_connections': active_conn + idle_conn + idle_in_tx
        }
    }
    
    # Check ClickHouse health
    try:
        clickhouse_host = os.getenv('CLICKHOUSE_HOST', 'clickhouse.data-storage.svc.cluster.local')
        clickhouse_port = os.getenv('CLICKHOUSE_PORT', '8123')
        clickhouse_url = f"http://{clickhouse_host}:{clickhouse_port}/ping"
        response = requests.get(clickhouse_url, timeout=10)
        
        if response.status_code == 200:
            system_metrics['clickhouse'] = {'status': 'healthy', 'response_time_ms': response.elapsed.total_seconds() * 1000}
        else:
            system_metrics['clickhouse'] = {'status': 'unhealthy', 'error': f"HTTP {response.status_code}"}
            
    except Exception as e:
        system_metrics['clickhouse'] = {'status': 'unreachable', 'error': str(e)}
    
    # Check Kafka health (simplified)
    try:
        # In a real implementation, you'd use kafka-python to check broker health
        system_metrics['kafka'] = {'status': 'unknown', 'note': 'Kafka health check not implemented'}
    except Exception as e:
        system_metrics['kafka'] = {'status': 'error', 'error': str(e)}
    
    # Generate alerts
    resource_alerts = []
    
    if long_queries > 0:
        resource_alerts.append(f"Database: {long_queries} long-running queries detected")
    
    if active_conn > 50:  # Assuming max connections around 100
        resource_alerts.append(f"Database: High connection count ({active_conn} active)")
    
    if system_metrics['clickhouse']['status'] != 'healthy':
        resource_alerts.append(f"ClickHouse: {system_metrics['clickhouse']['status']}")
    
    if resource_alerts:
        logging.warning(f"System resource alerts: {resource_alerts}")
        context['task_instance'].xcom_push(key='resource_alerts', value=resource_alerts)
    
    context['task_instance'].xcom_push(key='system_metrics', value=system_metrics)
    return system_metrics

def monitor_data_quality_trends(**context):
    """Monitor data quality trends over time"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get recent data quality metrics
    quality_trends_query = """
    WITH daily_quality AS (
        SELECT 
            DATE(created_at) as date,
            COUNT(*) as total_transactions,
            COUNT(CASE WHEN status = 'completed' THEN 1 END) as successful_transactions,
            COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_transactions,
            COUNT(CASE WHEN total_amount <= 0 THEN 1 END) as invalid_amounts,
            COUNT(CASE WHEN quantity <= 0 THEN 1 END) as invalid_quantities,
            AVG(CASE WHEN status = 'completed' THEN total_amount END) as avg_order_value
        FROM transactions 
        WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
        GROUP BY DATE(created_at)
        ORDER BY date DESC
    )
    SELECT 
        date,
        total_transactions,
        successful_transactions,
        failed_transactions,
        invalid_amounts,
        invalid_quantities,
        avg_order_value,
        ROUND((successful_transactions::DECIMAL / NULLIF(total_transactions, 0)) * 100, 2) as success_rate,
        ROUND(((invalid_amounts + invalid_quantities)::DECIMAL / NULLIF(total_transactions, 0)) * 100, 2) as error_rate
    FROM daily_quality
    """
    
    quality_trends = postgres_hook.get_records(quality_trends_query)
    
    if quality_trends:
        columns = ['date', 'total_transactions', 'successful_transactions', 'failed_transactions', 
                  'invalid_amounts', 'invalid_quantities', 'avg_order_value', 'success_rate', 'error_rate']
        
        trends_data = []
        quality_alerts = []
        
        for row in quality_trends:
            day_data = dict(zip(columns, row))
            day_data['date'] = str(day_data['date'])  # Convert date to string
            trends_data.append(day_data)
            
            # Check for quality issues
            if day_data['success_rate'] < 90:  # Less than 90% success rate
                quality_alerts.append(f"Low success rate on {day_data['date']}: {day_data['success_rate']}%")
            
            if day_data['error_rate'] > 5:  # More than 5% error rate
                quality_alerts.append(f"High error rate on {day_data['date']}: {day_data['error_rate']}%")
        
        # Calculate week-over-week trends
        if len(trends_data) >= 2:
            latest = trends_data[0]
            previous = trends_data[1]
            
            transaction_change = ((latest['total_transactions'] - previous['total_transactions']) / previous['total_transactions']) * 100 if previous['total_transactions'] > 0 else 0
            success_rate_change = latest['success_rate'] - previous['success_rate']
            
            trends_summary = {
                'transaction_volume_change_pct': round(transaction_change, 2),
                'success_rate_change_pct': round(success_rate_change, 2),
                'current_success_rate': latest['success_rate'],
                'current_error_rate': latest['error_rate']
            }
        else:
            trends_summary = {'note': 'Insufficient data for trend analysis'}
        
        if quality_alerts:
            logging.warning(f"Data quality alerts: {quality_alerts}")
            context['task_instance'].xcom_push(key='quality_alerts', value=quality_alerts)
        
        context['task_instance'].xcom_push(key='quality_trends', value={
            'daily_data': trends_data,
            'trends_summary': trends_summary
        })
        
        return trends_data
    else:
        logging.info("No data available for quality trend analysis")
        return []

def check_sla_compliance(**context):
    """Check SLA compliance for key metrics"""
    # Define SLAs
    slas = {
        'data_freshness_minutes': 60,      # Data should be < 1 hour old
        'pipeline_success_rate_pct': 95,   # 95% success rate
        'avg_processing_time_minutes': 30, # Processing should complete in 30 min
        'data_quality_score_pct': 90       # 90% data quality score
    }
    
    # Get monitoring results
    freshness_results = context['task_instance'].xcom_pull(key='freshness_results')
    dag_performance = context['task_instance'].xcom_pull(key='dag_performance')
    quality_trends = context['task_instance'].xcom_pull(key='quality_trends')
    
    sla_compliance = {}
    sla_violations = []
    
    # Check data freshness SLA
    if freshness_results:
        max_freshness = max(
            freshness_results.get('transactions', {}).get('minutes_since_latest', 0),
            freshness_results.get('user_events', {}).get('minutes_since_latest', 0)
        )
        
        sla_compliance['data_freshness'] = {
            'sla_minutes': slas['data_freshness_minutes'],
            'actual_minutes': max_freshness,
            'compliant': max_freshness <= slas['data_freshness_minutes']
        }
        
        if not sla_compliance['data_freshness']['compliant']:
            sla_violations.append(f"Data freshness SLA violated: {max_freshness:.0f} minutes (SLA: {slas['data_freshness_minutes']} minutes)")
    
    # Check pipeline success rate SLA
    if dag_performance:
        main_dag_performance = dag_performance.get('data_pipeline_main', {})
        success_rate = main_dag_performance.get('success_rate', 0)
        
        sla_compliance['pipeline_success_rate'] = {
            'sla_pct': slas['pipeline_success_rate_pct'],
            'actual_pct': success_rate,
            'compliant': success_rate >= slas['pipeline_success_rate_pct']
        }
        
        if not sla_compliance['pipeline_success_rate']['compliant']:
            sla_violations.append(f"Pipeline success rate SLA violated: {success_rate:.1f}% (SLA: {slas['pipeline_success_rate_pct']}%)")
    
    # Check processing time SLA
    if dag_performance:
        main_dag_performance = dag_performance.get('data_pipeline_main', {})
        avg_duration = main_dag_performance.get('avg_duration_minutes', 0)
        
        sla_compliance['processing_time'] = {
            'sla_minutes': slas['avg_processing_time_minutes'],
            'actual_minutes': avg_duration,
            'compliant': avg_duration <= slas['avg_processing_time_minutes']
        }
        
        if not sla_compliance['processing_time']['compliant']:
            sla_violations.append(f"Processing time SLA violated: {avg_duration:.1f} minutes (SLA: {slas['avg_processing_time_minutes']} minutes)")
    
    # Check data quality SLA
    if quality_trends and quality_trends.get('trends_summary'):
        current_success_rate = quality_trends['trends_summary'].get('current_success_rate', 0)
        
        sla_compliance['data_quality'] = {
            'sla_pct': slas['data_quality_score_pct'],
            'actual_pct': current_success_rate,
            'compliant': current_success_rate >= slas['data_quality_score_pct']
        }
        
        if not sla_compliance['data_quality']['compliant']:
            sla_violations.append(f"Data quality SLA violated: {current_success_rate:.1f}% (SLA: {slas['data_quality_score_pct']}%)")
    
    # Calculate overall SLA compliance
    compliant_slas = sum(1 for sla in sla_compliance.values() if sla.get('compliant', False))
    total_slas = len(sla_compliance)
    overall_compliance_pct = (compliant_slas / total_slas * 100) if total_slas > 0 else 0
    
    sla_summary = {
        'overall_compliance_pct': round(overall_compliance_pct, 1),
        'compliant_slas': compliant_slas,
        'total_slas': total_slas,
        'violations': sla_violations,
        'sla_details': sla_compliance
    }
    
    if sla_violations:
        logging.error(f"SLA violations detected: {sla_violations}")
    else:
        logging.info(f"All SLAs compliant ({overall_compliance_pct:.1f}%)")
    
    context['task_instance'].xcom_push(key='sla_compliance', value=sla_summary)
    return sla_summary

def generate_monitoring_dashboard(**context):
    """Generate comprehensive monitoring dashboard"""
    # Collect all monitoring results
    dag_performance = context['task_instance'].xcom_pull(key='dag_performance')
    freshness_results = context['task_instance'].xcom_pull(key='freshness_results')
    system_metrics = context['task_instance'].xcom_pull(key='system_metrics')
    quality_trends = context['task_instance'].xcom_pull(key='quality_trends')
    sla_compliance = context['task_instance'].xcom_pull(key='sla_compliance')
    
    # Collect all alerts
    freshness_alerts = context['task_instance'].xcom_pull(key='freshness_alerts') or []
    resource_alerts = context['task_instance'].xcom_pull(key='resource_alerts') or []
    quality_alerts = context['task_instance'].xcom_pull(key='quality_alerts') or []
    
    # Create comprehensive dashboard
    dashboard = {
        'monitoring_timestamp': datetime.now().isoformat(),
        'overall_health': 'healthy',  # Will be updated based on issues
        'dag_performance': dag_performance,
        'data_freshness': freshness_results,
        'system_resources': system_metrics,
        'data_quality_trends': quality_trends,
        'sla_compliance': sla_compliance,
        'alerts': {
            'freshness_alerts': freshness_alerts,
            'resource_alerts': resource_alerts,
            'quality_alerts': quality_alerts,
            'total_alerts': len(freshness_alerts) + len(resource_alerts) + len(quality_alerts)
        },
        'summary': {}
    }
    
    # Determine overall health
    total_alerts = dashboard['alerts']['total_alerts']
    sla_compliance_pct = sla_compliance.get('overall_compliance_pct', 100) if sla_compliance else 100
    
    if total_alerts == 0 and sla_compliance_pct >= 95:
        dashboard['overall_health'] = 'healthy'
    elif total_alerts <= 3 and sla_compliance_pct >= 90:
        dashboard['overall_health'] = 'warning'
    else:
        dashboard['overall_health'] = 'critical'
    
    # Generate summary
    dashboard['summary'] = {
        'overall_health': dashboard['overall_health'],
        'total_alerts': total_alerts,
        'sla_compliance_pct': sla_compliance_pct,
        'data_freshness_status': 'fresh' if all(r.get('is_fresh', False) for r in freshness_results.values()) else 'stale',
        'pipeline_success_rate': dag_performance.get('data_pipeline_main', {}).get('success_rate', 0) if dag_performance else 0,
        'system_status': 'healthy' if system_metrics.get('clickhouse', {}).get('status') == 'healthy' else 'degraded'
    }
    
    # Log dashboard summary
    logging.info("=== PIPELINE MONITORING DASHBOARD ===")
    logging.info(f"Overall Health: {dashboard['overall_health'].upper()}")
    logging.info(f"Total Alerts: {total_alerts}")
    logging.info(f"SLA Compliance: {sla_compliance_pct:.1f}%")
    logging.info(f"Pipeline Success Rate: {dashboard['summary']['pipeline_success_rate']:.1f}%")
    
    if total_alerts > 0:
        logging.warning("Active Alerts:")
        for alert_type, alerts in dashboard['alerts'].items():
            if alerts and alert_type != 'total_alerts':
                for alert in alerts:
                    logging.warning(f"  - {alert}")
    
    context['task_instance'].xcom_push(key='monitoring_dashboard', value=dashboard)
    return dashboard

def send_monitoring_alerts(**context):
    """Send alerts based on monitoring results"""
    dashboard = context['task_instance'].xcom_pull(key='monitoring_dashboard')
    
    if not dashboard:
        logging.error("No dashboard data available for alerting")
        return
    
    overall_health = dashboard['overall_health']
    total_alerts = dashboard['alerts']['total_alerts']
    
    if overall_health == 'critical' or total_alerts >= 5:
        # Critical alert
        alert_message = f"""
        🚨 CRITICAL PIPELINE ALERT 🚨
        
        Overall Health: {overall_health.upper()}
        Total Alerts: {total_alerts}
        SLA Compliance: {dashboard['summary']['sla_compliance_pct']:.1f}%
        
        Active Alerts:
        """
        
        for alert_type, alerts in dashboard['alerts'].items():
            if alerts and alert_type != 'total_alerts':
                alert_message += f"\n{alert_type.replace('_', ' ').title()}:\n"
                for alert in alerts:
                    alert_message += f"  - {alert}\n"
        
        alert_message += "\nImmediate attention required!"
        
        logging.error(alert_message)
        # In production: send to PagerDuty, Slack, etc.
        
    elif overall_health == 'warning' or total_alerts > 0:
        # Warning alert
        warning_message = f"""
        ⚠️ Pipeline Warning
        
        Overall Health: {overall_health.upper()}
        Total Alerts: {total_alerts}
        SLA Compliance: {dashboard['summary']['sla_compliance_pct']:.1f}%
        
        Please review and address issues.
        """
        
        logging.warning(warning_message)
        # In production: send to Slack, email, etc.
        
    else:
        # All good
        success_message = f"""
        ✅ Pipeline Health Check: ALL SYSTEMS OPERATIONAL
        
        SLA Compliance: {dashboard['summary']['sla_compliance_pct']:.1f}%
        Pipeline Success Rate: {dashboard['summary']['pipeline_success_rate']:.1f}%
        Data Freshness: {dashboard['summary']['data_freshness_status'].title()}
        
        No issues detected.
        """
        
        logging.info(success_message)
    
    return dashboard

# Task definitions
start_task = DummyOperator(
    task_id='start_monitoring',
    dag=dag,
)

# Monitoring task groups
with TaskGroup('performance_monitoring', dag=dag) as performance_group:
    
    monitor_dags = PythonOperator(
        task_id='monitor_dag_performance',
        python_callable=monitor_dag_performance,
        dag=dag,
    )
    
    monitor_resources = PythonOperator(
        task_id='monitor_system_resources',
        python_callable=monitor_system_resources,
        dag=dag,
    )

with TaskGroup('data_monitoring', dag=dag) as data_group:
    
    monitor_freshness = PythonOperator(
        task_id='monitor_data_freshness',
        python_callable=monitor_data_freshness,
        dag=dag,
    )
    
    monitor_quality = PythonOperator(
        task_id='monitor_quality_trends',
        python_callable=monitor_data_quality_trends,
        dag=dag,
    )

# SLA and reporting
check_slas = PythonOperator(
    task_id='check_sla_compliance',
    python_callable=check_sla_compliance,
    dag=dag,
)

generate_dashboard = PythonOperator(
    task_id='generate_monitoring_dashboard',
    python_callable=generate_monitoring_dashboard,
    dag=dag,
)

send_alerts = PythonOperator(
    task_id='send_monitoring_alerts',
    python_callable=send_monitoring_alerts,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_monitoring',
    dag=dag,
)

# Task dependencies
start_task >> [performance_group, data_group] >> check_slas >> generate_dashboard >> send_alerts >> end_task