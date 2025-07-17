"""
Maintenance Operations DAG - Database cleanup, optimization, and housekeeping
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator
from airflow.operators.dummy import DummyOperator
from airflow.providers.postgres.operators.postgres import PostgresOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.utils.task_group import TaskGroup
from airflow.utils.trigger_rule import TriggerRule
import logging

# Default arguments
default_args = {
    'owner': 'data-ops-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
    'catchup': False,
}

# DAG definition
dag = DAG(
    'maintenance_operations',
    default_args=default_args,
    description='Database maintenance, cleanup, and optimization tasks',
    schedule_interval='0 2 * * 0',  # Weekly on Sunday at 2 AM
    tags=['maintenance', 'cleanup', 'optimization'],
    doc_md=__doc__,
)

def analyze_database_size(**context):
    """Analyze database size and growth patterns"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get database size information
    size_query = """
    SELECT 
        schemaname,
        tablename,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size,
        pg_total_relation_size(schemaname||'.'||tablename) as size_bytes,
        pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
        pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size
    FROM pg_tables 
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
    ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
    """
    
    results = postgres_hook.get_records(size_query)
    
    total_size = 0
    table_sizes = []
    
    for row in results:
        schema, table, size_pretty, size_bytes, table_size, index_size = row
        total_size += size_bytes
        table_sizes.append({
            'schema': schema,
            'table': table,
            'size_pretty': size_pretty,
            'size_bytes': size_bytes,
            'table_size': table_size,
            'index_size': index_size
        })
        logging.info(f"Table {schema}.{table}: {size_pretty} (Table: {table_size}, Indexes: {index_size})")
    
    # Get row counts
    row_count_queries = {
        'users': 'SELECT COUNT(*) FROM users',
        'products': 'SELECT COUNT(*) FROM products',
        'transactions': 'SELECT COUNT(*) FROM transactions',
        'user_events': 'SELECT COUNT(*) FROM user_events'
    }
    
    row_counts = {}
    for table, query in row_count_queries.items():
        count = postgres_hook.get_first(query)[0]
        row_counts[table] = count
        logging.info(f"Table {table}: {count:,} rows")
    
    analysis_results = {
        'total_database_size_bytes': total_size,
        'total_database_size_pretty': f"{total_size / (1024**3):.2f} GB",
        'table_sizes': table_sizes,
        'row_counts': row_counts,
        'analysis_date': context['ds']
    }
    
    context['task_instance'].xcom_push(key='size_analysis', value=analysis_results)
    return analysis_results

def cleanup_old_data(**context):
    """Clean up old data based on retention policies"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    cleanup_results = {}
    
    # Define retention policies (in days)
    retention_policies = {
        'user_events': 90,      # Keep 90 days of events
        'daily_aggregations': 365,  # Keep 1 year of daily aggregations
        'backfill_progress': 180    # Keep 6 months of backfill progress
    }
    
    for table, retention_days in retention_policies.items():
        # Check if table exists
        check_table_query = """
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = %s
        )
        """
        
        table_exists = postgres_hook.get_first(check_table_query, parameters=[table])[0]
        
        if not table_exists:
            logging.info(f"Table {table} does not exist, skipping cleanup")
            continue
        
        # Count records to be deleted
        if table == 'user_events':
            count_query = f"SELECT COUNT(*) FROM {table} WHERE timestamp < NOW() - INTERVAL '{retention_days} days'"
            delete_query = f"DELETE FROM {table} WHERE timestamp < NOW() - INTERVAL '{retention_days} days'"
        elif table == 'daily_aggregations':
            count_query = f"SELECT COUNT(*) FROM {table} WHERE date < CURRENT_DATE - INTERVAL '{retention_days} days'"
            delete_query = f"DELETE FROM {table} WHERE date < CURRENT_DATE - INTERVAL '{retention_days} days'"
        elif table == 'backfill_progress':
            count_query = f"SELECT COUNT(*) FROM {table} WHERE completed_at < NOW() - INTERVAL '{retention_days} days'"
            delete_query = f"DELETE FROM {table} WHERE completed_at < NOW() - INTERVAL '{retention_days} days'"
        else:
            continue
        
        # Count records to be deleted
        records_to_delete = postgres_hook.get_first(count_query)[0]
        
        if records_to_delete > 0:
            # Perform deletion
            postgres_hook.run(delete_query)
            logging.info(f"Deleted {records_to_delete:,} old records from {table}")
            cleanup_results[table] = records_to_delete
        else:
            logging.info(f"No old records to delete from {table}")
            cleanup_results[table] = 0
    
    context['task_instance'].xcom_push(key='cleanup_results', value=cleanup_results)
    return cleanup_results

def vacuum_and_analyze(**context):
    """Run VACUUM and ANALYZE on all tables"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get all user tables
    tables_query = """
    SELECT schemaname, tablename 
    FROM pg_tables 
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
    ORDER BY tablename
    """
    
    tables = postgres_hook.get_records(tables_query)
    
    vacuum_results = {}
    
    for schema, table in tables:
        full_table_name = f"{schema}.{table}"
        
        try:
            # Run VACUUM ANALYZE
            vacuum_query = f"VACUUM ANALYZE {full_table_name}"
            postgres_hook.run(vacuum_query)
            
            logging.info(f"Successfully vacuumed and analyzed {full_table_name}")
            vacuum_results[full_table_name] = "success"
            
        except Exception as e:
            logging.error(f"Failed to vacuum {full_table_name}: {e}")
            vacuum_results[full_table_name] = f"failed: {str(e)}"
    
    context['task_instance'].xcom_push(key='vacuum_results', value=vacuum_results)
    return vacuum_results

def reindex_tables(**context):
    """Reindex tables to optimize query performance"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get index information
    index_query = """
    SELECT 
        schemaname,
        tablename,
        indexname,
        indexdef
    FROM pg_indexes 
    WHERE schemaname NOT IN ('information_schema', 'pg_catalog')
    ORDER BY schemaname, tablename, indexname
    """
    
    indexes = postgres_hook.get_records(index_query)
    
    reindex_results = {}
    
    # Focus on high-traffic tables
    high_traffic_tables = ['transactions', 'user_events', 'users', 'products']
    
    for schema, table, index_name, index_def in indexes:
        if table in high_traffic_tables:
            full_index_name = f"{schema}.{index_name}"
            
            try:
                # Reindex
                reindex_query = f"REINDEX INDEX {full_index_name}"
                postgres_hook.run(reindex_query)
                
                logging.info(f"Successfully reindexed {full_index_name}")
                reindex_results[full_index_name] = "success"
                
            except Exception as e:
                logging.error(f"Failed to reindex {full_index_name}: {e}")
                reindex_results[full_index_name] = f"failed: {str(e)}"
    
    context['task_instance'].xcom_push(key='reindex_results', value=reindex_results)
    return reindex_results

def update_table_statistics(**context):
    """Update table statistics for query optimization"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    # Get table statistics
    stats_query = """
    SELECT 
        schemaname,
        tablename,
        n_tup_ins as inserts,
        n_tup_upd as updates,
        n_tup_del as deletes,
        n_live_tup as live_tuples,
        n_dead_tup as dead_tuples,
        last_vacuum,
        last_autovacuum,
        last_analyze,
        last_autoanalyze
    FROM pg_stat_user_tables
    ORDER BY n_live_tup DESC
    """
    
    stats = postgres_hook.get_records(stats_query)
    
    statistics_results = []
    
    for row in stats:
        schema, table, inserts, updates, deletes, live_tuples, dead_tuples, last_vacuum, last_autovacuum, last_analyze, last_autoanalyze = row
        
        # Calculate dead tuple percentage
        dead_percentage = (dead_tuples / max(live_tuples, 1)) * 100 if live_tuples > 0 else 0
        
        table_stats = {
            'schema': schema,
            'table': table,
            'inserts': inserts,
            'updates': updates,
            'deletes': deletes,
            'live_tuples': live_tuples,
            'dead_tuples': dead_tuples,
            'dead_percentage': round(dead_percentage, 2),
            'last_vacuum': str(last_vacuum) if last_vacuum else None,
            'last_autovacuum': str(last_autovacuum) if last_autovacuum else None,
            'last_analyze': str(last_analyze) if last_analyze else None,
            'last_autoanalyze': str(last_autoanalyze) if last_autoanalyze else None
        }
        
        statistics_results.append(table_stats)
        
        logging.info(f"Table {schema}.{table}: {live_tuples:,} live, {dead_tuples:,} dead ({dead_percentage:.1f}%)")
    
    context['task_instance'].xcom_push(key='table_statistics', value=statistics_results)
    return statistics_results

def check_database_health(**context):
    """Perform comprehensive database health checks"""
    postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
    
    health_checks = {}
    
    # Check for long-running queries
    long_queries_query = """
    SELECT 
        pid,
        now() - pg_stat_activity.query_start AS duration,
        query,
        state
    FROM pg_stat_activity 
    WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
      AND state = 'active'
    """
    
    long_queries = postgres_hook.get_records(long_queries_query)
    health_checks['long_running_queries'] = len(long_queries)
    
    if long_queries:
        logging.warning(f"Found {len(long_queries)} long-running queries")
        for pid, duration, query, state in long_queries:
            logging.warning(f"PID {pid}: {duration} - {query[:100]}...")
    
    # Check for blocked queries
    blocked_queries_query = """
    SELECT 
        blocked_locks.pid AS blocked_pid,
        blocked_activity.usename AS blocked_user,
        blocking_locks.pid AS blocking_pid,
        blocking_activity.usename AS blocking_user,
        blocked_activity.query AS blocked_statement,
        blocking_activity.query AS blocking_statement
    FROM pg_catalog.pg_locks blocked_locks
    JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
    JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
        AND blocking_locks.DATABASE IS NOT DISTINCT FROM blocked_locks.DATABASE
        AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
        AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
        AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
        AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
        AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
        AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
        AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
        AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
        AND blocking_locks.pid != blocked_locks.pid
    JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
    WHERE NOT blocked_locks.GRANTED
    """
    
    blocked_queries = postgres_hook.get_records(blocked_queries_query)
    health_checks['blocked_queries'] = len(blocked_queries)
    
    if blocked_queries:
        logging.warning(f"Found {len(blocked_queries)} blocked queries")
    
    # Check database connections
    connections_query = """
    SELECT 
        state,
        COUNT(*) as count
    FROM pg_stat_activity 
    GROUP BY state
    """
    
    connections = postgres_hook.get_records(connections_query)
    health_checks['connections'] = {state: count for state, count in connections}
    
    # Check for unused indexes
    unused_indexes_query = """
    SELECT 
        schemaname,
        tablename,
        indexname,
        idx_tup_read,
        idx_tup_fetch
    FROM pg_stat_user_indexes 
    WHERE idx_tup_read = 0 AND idx_tup_fetch = 0
      AND schemaname NOT IN ('information_schema', 'pg_catalog')
    """
    
    unused_indexes = postgres_hook.get_records(unused_indexes_query)
    health_checks['unused_indexes'] = len(unused_indexes)
    
    if unused_indexes:
        logging.info(f"Found {len(unused_indexes)} potentially unused indexes")
        for schema, table, index, reads, fetches in unused_indexes:
            logging.info(f"Unused index: {schema}.{index} on table {table}")
    
    context['task_instance'].xcom_push(key='health_checks', value=health_checks)
    return health_checks

def generate_maintenance_report(**context):
    """Generate comprehensive maintenance report"""
    # Collect results from all tasks
    size_analysis = context['task_instance'].xcom_pull(key='size_analysis')
    cleanup_results = context['task_instance'].xcom_pull(key='cleanup_results')
    vacuum_results = context['task_instance'].xcom_pull(key='vacuum_results')
    reindex_results = context['task_instance'].xcom_pull(key='reindex_results')
    table_statistics = context['task_instance'].xcom_pull(key='table_statistics')
    health_checks = context['task_instance'].xcom_pull(key='health_checks')
    
    # Generate comprehensive report
    report = {
        'maintenance_date': context['ds'],
        'database_size': size_analysis,
        'cleanup_summary': {
            'total_records_deleted': sum(cleanup_results.values()) if cleanup_results else 0,
            'tables_cleaned': cleanup_results
        },
        'vacuum_summary': {
            'tables_processed': len(vacuum_results) if vacuum_results else 0,
            'successful_vacuums': len([r for r in vacuum_results.values() if r == 'success']) if vacuum_results else 0,
            'failed_vacuums': len([r for r in vacuum_results.values() if r != 'success']) if vacuum_results else 0
        },
        'reindex_summary': {
            'indexes_processed': len(reindex_results) if reindex_results else 0,
            'successful_reindexes': len([r for r in reindex_results.values() if r == 'success']) if reindex_results else 0,
            'failed_reindexes': len([r for r in reindex_results.values() if r != 'success']) if reindex_results else 0
        },
        'health_summary': health_checks,
        'recommendations': []
    }
    
    # Generate recommendations
    if health_checks:
        if health_checks.get('long_running_queries', 0) > 0:
            report['recommendations'].append("Investigate long-running queries for optimization")
        
        if health_checks.get('blocked_queries', 0) > 0:
            report['recommendations'].append("Review blocking queries and consider query optimization")
        
        if health_checks.get('unused_indexes', 0) > 5:
            report['recommendations'].append("Consider dropping unused indexes to save space")
    
    if table_statistics:
        high_dead_tuple_tables = [t for t in table_statistics if t['dead_percentage'] > 20]
        if high_dead_tuple_tables:
            report['recommendations'].append(f"Tables with high dead tuple percentage need more frequent vacuuming: {[t['table'] for t in high_dead_tuple_tables]}")
    
    if not report['recommendations']:
        report['recommendations'].append("Database maintenance completed successfully. No issues detected.")
    
    # Log summary
    logging.info("=== MAINTENANCE REPORT ===")
    logging.info(f"Database Size: {size_analysis['total_database_size_pretty'] if size_analysis else 'N/A'}")
    logging.info(f"Records Cleaned: {report['cleanup_summary']['total_records_deleted']:,}")
    logging.info(f"Tables Vacuumed: {report['vacuum_summary']['tables_processed']}")
    logging.info(f"Indexes Reindexed: {report['reindex_summary']['indexes_processed']}")
    logging.info(f"Health Issues: Long queries: {health_checks.get('long_running_queries', 0)}, Blocked queries: {health_checks.get('blocked_queries', 0)}")
    
    context['task_instance'].xcom_push(key='maintenance_report', value=report)
    return report

# Task definitions
start_task = DummyOperator(
    task_id='start_maintenance',
    dag=dag,
)

# Analysis tasks
analyze_size = PythonOperator(
    task_id='analyze_database_size',
    python_callable=analyze_database_size,
    dag=dag,
)

# Cleanup task group
with TaskGroup('cleanup_operations', dag=dag) as cleanup_group:
    
    cleanup_data = PythonOperator(
        task_id='cleanup_old_data',
        python_callable=cleanup_old_data,
        dag=dag,
    )
    
    vacuum_analyze = PythonOperator(
        task_id='vacuum_and_analyze',
        python_callable=vacuum_and_analyze,
        dag=dag,
    )
    
    reindex = PythonOperator(
        task_id='reindex_tables',
        python_callable=reindex_tables,
        dag=dag,
    )

# Monitoring tasks
update_stats = PythonOperator(
    task_id='update_table_statistics',
    python_callable=update_table_statistics,
    dag=dag,
)

health_check = PythonOperator(
    task_id='check_database_health',
    python_callable=check_database_health,
    dag=dag,
)

# Reporting
generate_report = PythonOperator(
    task_id='generate_maintenance_report',
    python_callable=generate_maintenance_report,
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

end_task = DummyOperator(
    task_id='end_maintenance',
    trigger_rule=TriggerRule.NONE_FAILED_MIN_ONE_SUCCESS,
    dag=dag,
)

# Task dependencies
start_task >> analyze_size >> cleanup_group >> [update_stats, health_check] >> generate_report >> end_task

# Within cleanup group - run in parallel
cleanup_data
vacuum_analyze
reindex