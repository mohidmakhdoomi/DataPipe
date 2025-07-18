"""
Environment Configuration for Airflow DAGs
Centralizes environment-specific settings and connection details
"""

import os
from typing import Dict, Any


class EnvironmentConfig:
    """Environment configuration manager for Airflow DAGs"""
    
    def __init__(self):
        self.env = os.getenv('AIRFLOW_ENV', 'development')
        self.is_production = self.env == 'production'
        self.is_kubernetes = os.getenv('KUBERNETES_SERVICE_HOST') is not None
    
    @property
    def postgres_config(self) -> Dict[str, str]:
        """Get PostgreSQL configuration based on environment"""
        if self.is_kubernetes:
            # Kubernetes service names
            host = 'postgres.data-storage.svc.cluster.local'
        elif self.env == 'development':
            # Local docker-compose
            host = 'postgres'
        else:
            # Default fallback
            host = os.getenv('POSTGRES_HOST', '127.0.0.1')
        
        return {
            'host': host,
            'port': os.getenv('POSTGRES_PORT', '5432'),
            'database': os.getenv('POSTGRES_DB', 'transactions_db'),
            'user': os.getenv('POSTGRES_USER', 'postgres'),
            'password': os.getenv('POSTGRES_PASSWORD', 'postgres_password')
        }
    
    @property
    def clickhouse_config(self) -> Dict[str, str]:
        """Get ClickHouse configuration based on environment"""
        if self.is_kubernetes:
            # Kubernetes service names
            host = 'clickhouse.data-storage.svc.cluster.local'
        elif self.env == 'development':
            # Local docker-compose
            host = 'clickhouse'
        else:
            # Default fallback
            host = os.getenv('CLICKHOUSE_HOST', 'localhost')
        
        return {
            'host': host,
            'port': os.getenv('CLICKHOUSE_PORT', '8123'),
            'database': os.getenv('CLICKHOUSE_DB', 'analytics'),
            'user': os.getenv('CLICKHOUSE_USER', 'analytics_user'),
            'password': os.getenv('CLICKHOUSE_PASSWORD', 'analytics_password'),
            'url': f"http://{host}:{os.getenv('CLICKHOUSE_PORT', '8123')}"
        }
    
    @property
    def snowflake_config(self) -> Dict[str, str]:
        """Get Snowflake configuration"""
        return {
            'account': os.getenv('SNOWFLAKE_ACCOUNT', ''),
            'user': os.getenv('SNOWFLAKE_USER', ''),
            'password': os.getenv('SNOWFLAKE_PASSWORD', ''),
            'role': os.getenv('SNOWFLAKE_ROLE', ''),
            'database': os.getenv('SNOWFLAKE_DATABASE', ''),
            'warehouse': os.getenv('SNOWFLAKE_WAREHOUSE', ''),
            'schema': os.getenv('SNOWFLAKE_SCHEMA', 'PUBLIC')
        }
    
    @property
    def dbt_config(self) -> Dict[str, Any]:
        """Get dbt configuration"""
        # Determine dbt target based on Snowflake availability
        target = 'snowflake' if self.snowflake_config['account'] else 'dev'
        
        # Determine dbt project path based on environment
        if self.is_kubernetes or self.env == 'production':
            project_path = '/opt/airflow/dbt'
        else:
            project_path = '../dbt'  # Local development
        
        return {
            'target': target,
            'project_path': project_path,
            'profiles_dir': f"{project_path}/profiles" if self.is_kubernetes else None
        }
    
    @property
    def aws_config(self) -> Dict[str, str]:
        """Get AWS configuration"""
        return {
            'access_key_id': os.getenv('AWS_ACCESS_KEY_ID', ''),
            'secret_access_key': os.getenv('AWS_SECRET_ACCESS_KEY', ''),
            'region': os.getenv('AWS_DEFAULT_REGION', 'us-west-2'),
            's3_bucket': os.getenv('AWS_S3_BUCKET', 'data-pipeline-bucket')
        }
    
    def get_all_env_vars(self) -> Dict[str, str]:
        """Get all environment variables for subprocess calls"""
        env_vars = os.environ.copy()
        
        # Add PostgreSQL config
        postgres = self.postgres_config
        env_vars.update({
            'POSTGRES_HOST': postgres['host'],
            'POSTGRES_PORT': postgres['port'],
            'POSTGRES_DB': postgres['database'],
            'POSTGRES_USER': postgres['user'],
            'POSTGRES_PASSWORD': postgres['password']
        })
        
        # Add Snowflake config
        snowflake = self.snowflake_config
        env_vars.update({
            'SNOWFLAKE_ACCOUNT': snowflake['account'],
            'SNOWFLAKE_USER': snowflake['user'],
            'SNOWFLAKE_PASSWORD': snowflake['password'],
            'SNOWFLAKE_ROLE': snowflake['role'],
            'SNOWFLAKE_DATABASE': snowflake['database'],
            'SNOWFLAKE_WAREHOUSE': snowflake['warehouse']
        })
        
        # Add AWS config
        aws = self.aws_config
        env_vars.update({
            'AWS_ACCESS_KEY_ID': aws['access_key_id'],
            'AWS_SECRET_ACCESS_KEY': aws['secret_access_key'],
            'AWS_DEFAULT_REGION': aws['region']
        })
        
        return env_vars
    
    def log_config(self, logger):
        """Log current configuration (without sensitive data)"""
        logger.info(f"Environment: {self.env}")
        logger.info(f"Is Production: {self.is_production}")
        logger.info(f"Is Kubernetes: {self.is_kubernetes}")
        logger.info(f"PostgreSQL Host: {self.postgres_config['host']}")
        logger.info(f"ClickHouse Host: {self.clickhouse_config['host']}")
        logger.info(f"dbt Target: {self.dbt_config['target']}")
        logger.info(f"dbt Project Path: {self.dbt_config['project_path']}")
        
        if self.snowflake_config['account']:
            logger.info(f"Snowflake Account: {self.snowflake_config['account']}")
        else:
            logger.info("Snowflake: Not configured")


# Global instance
config = EnvironmentConfig()