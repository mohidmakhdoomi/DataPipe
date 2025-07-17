"""
Airflow local settings for Docker deployment
"""

import os
from airflow.configuration import conf

# Configure logging
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
    },
    'loggers': {
        'airflow.processor': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'airflow.task': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    }
}

# Environment-specific configurations
if os.getenv('AIRFLOW_ENV') == 'production':
    # Production settings
    LOGGING_CONFIG['root']['level'] = 'WARNING'
    LOGGING_CONFIG['loggers']['airflow.processor']['level'] = 'WARNING'
    LOGGING_CONFIG['loggers']['airflow.task']['level'] = 'INFO'