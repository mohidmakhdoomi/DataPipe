"""
Local Airflow settings for development environment
"""

import os
from airflow.configuration import conf

# Custom logging configuration
LOGGING_CONFIG = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'airflow': {
            'format': '[%(asctime)s] {%(filename)s:%(lineno)d} %(levelname)s - %(message)s'
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'airflow',
            'stream': 'ext://sys.stdout'
        },
        'task': {
            'class': 'logging.FileHandler',
            'formatter': 'airflow',
            'filename': '/opt/airflow/logs/task.log'
        },
    },
    'loggers': {
        'airflow.processor': {
            'handlers': ['console', 'task'],
            'level': 'INFO',
            'propagate': False,
        },
        'airflow.task': {
            'handlers': ['console', 'task'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    }
}

# Custom task policy (optional)
def task_policy(task):
    """Apply custom policies to tasks"""
    # Example: Set default retries for all tasks
    if not hasattr(task, 'retries') or task.retries is None:
        task.retries = 2
    
    # Example: Set default email on failure
    if not hasattr(task, 'email_on_failure'):
        task.email_on_failure = False

# Custom DAG policy (optional)
def dag_policy(dag):
    """Apply custom policies to DAGs"""
    # Example: Set default tags
    if not dag.tags:
        dag.tags = ['data-pipeline']
    
    # Example: Set default email settings
    if not dag.default_args.get('email_on_failure'):
        dag.default_args['email_on_failure'] = False