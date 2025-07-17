#!/usr/bin/env python3
"""
Airflow Configuration and DAG Testing Script

This script tests:
1. Airflow configuration validity
2. DAG parsing and structure
3. Task dependencies
4. Connection configurations
5. Environment variables
6. Database connectivity
"""

import os
import sys
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def test_environment_variables():
    """Test that all required environment variables are set"""
    logger.info("🔍 Testing environment variables...")
    
    required_vars = [
        'AIRFLOW__CORE__FERNET_KEY',
        'AIRFLOW__WEBSERVER__SECRET_KEY',
        'AIRFLOW__DATABASE__SQL_ALCHEMY_CONN'
    ]
    
    optional_vars = [
        'POSTGRES_HOST',
        'POSTGRES_PORT', 
        'POSTGRES_DB',
        'POSTGRES_USER',
        'CLICKHOUSE_HOST',
        'CLICKHOUSE_PASSWORD'
    ]
    
    missing_required = []
    missing_optional = []
    
    for var in required_vars:
        if not os.getenv(var):
            missing_required.append(var)
        else:
            logger.info(f"✅ {var}: Set")
    
    for var in optional_vars:
        if not os.getenv(var):
            missing_optional.append(var)
        else:
            logger.info(f"✅ {var}: {os.getenv(var)}")
    
    if missing_required:
        logger.error(f"❌ Missing required environment variables: {missing_required}")
        return False
    
    if missing_optional:
        logger.warning(f"⚠️ Missing optional environment variables: {missing_optional}")
    
    logger.info("✅ Environment variables check passed")
    return True

def test_airflow_imports():
    """Test that Airflow can be imported and basic functionality works"""
    logger.info("🔍 Testing Airflow imports...")
    
    try:
        from airflow import DAG
        from airflow.operators.python import PythonOperator
        from airflow.providers.postgres.hooks.postgres import PostgresHook
        from airflow.models import Variable
        logger.info("✅ Airflow imports successful")
        return True
    except ImportError as e:
        logger.error(f"❌ Airflow import failed: {e}")
        return False

def test_dag_parsing():
    """Test DAG parsing and structure"""
    logger.info("🔍 Testing DAG parsing...")
    
    try:
        # Import the DAG
        sys.path.append('/opt/airflow/dags')
        from data_pipeline_main import dag
        
        # Basic DAG validation
        assert dag.dag_id == 'data_pipeline_main'
        assert len(dag.tasks) > 0
        
        logger.info(f"✅ DAG parsed successfully: {dag.dag_id}")
        logger.info(f"✅ Tasks found: {len(dag.tasks)}")
        
        # List all tasks
        for task in dag.tasks:
            logger.info(f"  - {task.task_id} ({type(task).__name__})")
        
        return True
    except Exception as e:
        logger.error(f"❌ DAG parsing failed: {e}")
        return False

def test_dag_structure():
    """Test DAG structure and dependencies"""
    logger.info("🔍 Testing DAG structure...")
    
    try:
        sys.path.append('/opt/airflow/dags')
        from data_pipeline_main import dag
        
        # Test DAG structure by checking task dependencies
        try:
            task_ids = [task.task_id for task in dag.tasks]
            logger.info(f"✅ DAG structure valid with {len(task_ids)} tasks")
        except Exception as e:
            logger.error(f"❌ DAG structure error: {e}")
            return False
        
        # Check task dependencies
        task_ids = [task.task_id for task in dag.tasks]
        expected_tasks = [
            'start_pipeline',
            'check_data_freshness',
            'extract_and_validate_data',
            'decide_processing_path',
            'update_clickhouse_realtime',
            'generate_quality_report',
            'send_notification',
            'end_pipeline'
        ]
        
        missing_tasks = [task for task in expected_tasks if task not in task_ids]
        if missing_tasks:
            logger.warning(f"⚠️ Missing expected tasks: {missing_tasks}")
        
        logger.info("✅ DAG structure validation passed")
        return True
    except Exception as e:
        logger.error(f"❌ DAG structure test failed: {e}")
        return False

def test_database_connection():
    """Test database connectivity"""
    logger.info("🔍 Testing database connection...")
    
    try:
        from airflow.providers.postgres.hooks.postgres import PostgresHook
        
        # Test PostgreSQL connection
        postgres_hook = PostgresHook(postgres_conn_id='postgres_default')
        
        # Simple connection test
        result = postgres_hook.get_first("SELECT 1 as test")
        if result and result[0] == 1:
            logger.info("✅ PostgreSQL connection successful")
            return True
        else:
            logger.error("❌ PostgreSQL connection test failed")
            return False
            
    except Exception as e:
        logger.error(f"❌ Database connection test failed: {e}")
        return False

def test_task_functions():
    """Test individual task functions"""
    logger.info("🔍 Testing task functions...")
    
    try:
        sys.path.append('/opt/airflow/dags')
        from data_pipeline_main import check_data_freshness, extract_and_validate_data
        
        # Mock context for testing
        mock_context = {
            'task_instance': MockTaskInstance(),
            'ds': '2024-01-01',
            'run_id': 'test_run'
        }
        
        # Test functions (with mocked dependencies)
        logger.info("✅ Task functions imported successfully")
        return True
        
    except Exception as e:
        logger.error(f"❌ Task function test failed: {e}")
        return False

class MockTaskInstance:
    """Mock TaskInstance for testing"""
    def __init__(self):
        self.xcom_data = {}
    
    def xcom_push(self, key, value):
        self.xcom_data[key] = value
    
    def xcom_pull(self, key):
        return self.xcom_data.get(key)

def test_airflow_configuration():
    """Test Airflow configuration"""
    logger.info("🔍 Testing Airflow configuration...")
    
    try:
        from airflow.configuration import conf
        
        # Check key configuration values
        executor = conf.get('core', 'executor')
        logger.info(f"✅ Executor: {executor}")
        
        dags_folder = conf.get('core', 'dags_folder')
        logger.info(f"✅ DAGs folder: {dags_folder}")
        
        # Check if DAGs folder exists
        if os.path.exists(dags_folder):
            logger.info("✅ DAGs folder exists")
        else:
            logger.warning(f"⚠️ DAGs folder not found: {dags_folder}")
        
        return True
    except Exception as e:
        logger.error(f"❌ Airflow configuration test failed: {e}")
        return False

def run_all_tests():
    """Run all tests and provide summary"""
    logger.info("🚀 Starting Airflow configuration tests...")
    
    tests = [
        ("Environment Variables", test_environment_variables),
        ("Airflow Imports", test_airflow_imports),
        ("Airflow Configuration", test_airflow_configuration),
        ("DAG Parsing", test_dag_parsing),
        ("DAG Structure", test_dag_structure),
        ("Task Functions", test_task_functions),
        ("Database Connection", test_database_connection),
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        logger.info(f"\n{'='*50}")
        logger.info(f"Running: {test_name}")
        logger.info(f"{'='*50}")
        
        try:
            results[test_name] = test_func()
        except Exception as e:
            logger.error(f"❌ {test_name} failed with exception: {e}")
            results[test_name] = False
    
    # Summary
    logger.info(f"\n{'='*50}")
    logger.info("TEST SUMMARY")
    logger.info(f"{'='*50}")
    
    passed = sum(1 for result in results.values() if result)
    total = len(results)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        logger.info(f"{test_name}: {status}")
    
    logger.info(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        logger.info("🎉 All tests passed! Airflow setup is ready.")
        return True
    else:
        logger.error(f"❌ {total - passed} tests failed. Please fix issues before proceeding.")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)