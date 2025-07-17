"""
Snowflake Plugin for Airflow - Custom operators and hooks for Snowflake integration
"""

from airflow.plugins_manager import AirflowPlugin
from airflow.providers.snowflake.hooks.snowflake import SnowflakeHook
from airflow.providers.snowflake.operators.snowflake import SnowflakeOperator
from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults
import logging


class SnowflakeDataQualityOperator(BaseOperator):
    """
    Custom operator for running data quality checks in Snowflake
    """
    
    @apply_defaults
    def __init__(
        self,
        snowflake_conn_id='snowflake_default',
        database=None,
        schema=None,
        warehouse=None,
        quality_checks=None,
        *args,
        **kwargs
    ):
        super().__init__(*args, **kwargs)
        self.snowflake_conn_id = snowflake_conn_id
        self.database = database
        self.schema = schema
        self.warehouse = warehouse
        self.quality_checks = quality_checks or []
    
    def execute(self, context):
        """Execute data quality checks in Snowflake"""
        hook = SnowflakeHook(snowflake_conn_id=self.snowflake_conn_id)
        
        # Set context if provided
        if self.database:
            hook.run(f"USE DATABASE {self.database}")
        if self.schema:
            hook.run(f"USE SCHEMA {self.schema}")
        if self.warehouse:
            hook.run(f"USE WAREHOUSE {self.warehouse}")
        
        results = {}
        
        for check_name, check_sql in self.quality_checks.items():
            try:
                result = hook.get_first(check_sql)
                results[check_name] = result
                logging.info(f"Quality check '{check_name}': {result}")
                
                # If the check returns a count > 0, it might indicate an issue
                if isinstance(result, (list, tuple)) and len(result) > 0:
                    if isinstance(result[0], (int, float)) and result[0] > 0:
                        logging.warning(f"Quality check '{check_name}' found {result[0]} issues")
                
            except Exception as e:
                logging.error(f"Quality check '{check_name}' failed: {e}")
                results[check_name] = {'error': str(e)}
        
        # Push results to XCom
        context['task_instance'].xcom_push(key='quality_check_results', value=results)
        
        return results


class SnowflakeTableStatsOperator(BaseOperator):
    """
    Custom operator for gathering table statistics in Snowflake
    """
    
    @apply_defaults
    def __init__(
        self,
        snowflake_conn_id='snowflake_default',
        tables=None,
        database=None,
        schema=None,
        *args,
        **kwargs
    ):
        super().__init__(*args, **kwargs)
        self.snowflake_conn_id = snowflake_conn_id
        self.tables = tables or []
        self.database = database
        self.schema = schema
    
    def execute(self, context):
        """Gather table statistics"""
        hook = SnowflakeHook(snowflake_conn_id=self.snowflake_conn_id)
        
        # Set context
        if self.database:
            hook.run(f"USE DATABASE {self.database}")
        if self.schema:
            hook.run(f"USE SCHEMA {self.schema}")
        
        stats = {}
        
        for table in self.tables:
            try:
                # Get row count
                row_count = hook.get_first(f"SELECT COUNT(*) FROM {table}")[0]
                
                # Get table info
                table_info = hook.get_records(f"""
                    SELECT 
                        TABLE_NAME,
                        ROW_COUNT,
                        BYTES,
                        LAST_ALTERED
                    FROM INFORMATION_SCHEMA.TABLES 
                    WHERE TABLE_NAME = '{table.upper()}'
                """)
                
                stats[table] = {
                    'row_count': row_count,
                    'table_info': table_info[0] if table_info else None
                }
                
                logging.info(f"Table {table}: {row_count} rows")
                
            except Exception as e:
                logging.error(f"Failed to get stats for table {table}: {e}")
                stats[table] = {'error': str(e)}
        
        context['task_instance'].xcom_push(key='table_stats', value=stats)
        return stats


class SnowflakePlugin(AirflowPlugin):
    """Snowflake plugin for custom operators"""
    name = "snowflake_plugin"
    operators = [SnowflakeDataQualityOperator, SnowflakeTableStatsOperator]