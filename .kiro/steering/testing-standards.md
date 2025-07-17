---
inclusion: fileMatch
fileMatchPattern: '**/test*.py'
---

# Testing Standards

## Test Strategy Overview

### Testing Pyramid
Our testing approach follows the testing pyramid principle:

```
    /\
   /  \     E2E Tests (Few)
  /____\    - Full pipeline integration
 /      \   - User acceptance scenarios
/________\  Integration Tests (Some)
           - Component interactions
           - Database integration
           - API contract testing
___________
Unit Tests (Many)
- Individual function testing
- Business logic validation
- Data transformation testing
```

## Unit Testing Standards

### Test Structure and Naming
```python
import pytest
from unittest.mock import Mock, patch
from datetime import datetime, date
from typing import Dict, Any

# Test file naming: test_<module_name>.py
# Test function naming: test_<function_name>_<scenario>_<expected_result>

class TestUserDataProcessor:
    """Test class for UserDataProcessor functionality"""
    
    def test_process_user_data_valid_input_returns_processed_data(self):
        """Test that valid user data is processed correctly"""
        # Arrange
        processor = UserDataProcessor()
        input_data = {
            'user_id': 'user123',
            'email': 'test@example.com',
            'registration_date': '2024-01-01'
        }
        
        # Act
        result = processor.process_user_data(input_data)
        
        # Assert
        assert result['user_id'] == 'user123'
        assert result['email'] == 'test@example.com'
        assert isinstance(result['registration_date'], date)
    
    def test_process_user_data_invalid_email_raises_validation_error(self):
        """Test that invalid email raises ValidationError"""
        # Arrange
        processor = UserDataProcessor()
        input_data = {
            'user_id': 'user123',
            'email': 'invalid-email',
            'registration_date': '2024-01-01'
        }
        
        # Act & Assert
        with pytest.raises(ValidationError) as exc_info:
            processor.process_user_data(input_data)
        
        assert 'Invalid email format' in str(exc_info.value)
    
    @patch('user_processor.database_client')
    def test_save_user_data_database_error_handles_gracefully(self, mock_db):
        """Test that database errors are handled gracefully"""
        # Arrange
        mock_db.save.side_effect = DatabaseError("Connection failed")
        processor = UserDataProcessor()
        user_data = {'user_id': 'user123', 'email': 'test@example.com'}
        
        # Act & Assert
        with pytest.raises(DatabaseError):
            processor.save_user_data(user_data)
        
        # Verify error was logged
        assert mock_db.save.called
```

### Data Testing with dbt
```python
# tests/test_dbt_models.py
import pytest
from dbt.cli.main import dbtRunner
import pandas as pd

class TestDbtModels:
    """Test dbt model functionality and data quality"""
    
    @pytest.fixture(scope="class")
    def dbt_runner(self):
        """Initialize dbt runner for testing"""
        return dbtRunner()
    
    def test_stg_users_model_runs_successfully(self, dbt_runner):
        """Test that staging users model runs without errors"""
        # Run specific model
        result = dbt_runner.invoke(['run', '--select', 'stg_users'])
        assert result.success
    
    def test_dim_users_data_quality(self, dbt_runner):
        """Test data quality of users dimension"""
        # Run model
        dbt_runner.invoke(['run', '--select', 'dim_users'])
        
        # Connect to test database and validate
        df = pd.read_sql("""
            SELECT 
                COUNT(*) as total_records,
                COUNT(CASE WHEN user_id IS NULL THEN 1 END) as null_user_ids,
                COUNT(CASE WHEN email IS NULL THEN 1 END) as null_emails,
                COUNT(DISTINCT user_id) as unique_users
            FROM marts.dim_users
        """, connection)
        
        # Assertions
        assert df.iloc[0]['null_user_ids'] == 0, "Found null user IDs"
        assert df.iloc[0]['null_emails'] == 0, "Found null emails"
        assert df.iloc[0]['total_records'] == df.iloc[0]['unique_users'], "Duplicate user IDs found"
    
    def test_revenue_consistency_across_models(self, dbt_runner):
        """Test that revenue calculations are consistent"""
        # Run related models
        dbt_runner.invoke(['run', '--select', 'dim_users', 'fact_transactions'])
        
        # Check revenue consistency
        df = pd.read_sql("""
            SELECT 
                ABS(
                    (SELECT SUM(total_revenue) FROM marts.dim_users) -
                    (SELECT SUM(recognized_revenue) FROM marts.fact_transactions)
                ) as revenue_difference
        """, connection)
        
        assert df.iloc[0]['revenue_difference'] < 1, "Revenue inconsistency detected"
```

### Mock Data Generation
```python
# tests/fixtures/data_fixtures.py
import pytest
from faker import Faker
from datetime import datetime, timedelta
import random

fake = Faker()

@pytest.fixture
def sample_user_data():
    """Generate sample user data for testing"""
    return {
        'user_id': fake.uuid4(),
        'email': fake.email(),
        'first_name': fake.first_name(),
        'last_name': fake.last_name(),
        'date_of_birth': fake.date_of_birth(minimum_age=18, maximum_age=80),
        'registration_date': fake.date_time_between(start_date='-2y', end_date='now'),
        'tier': random.choice(['bronze', 'silver', 'gold', 'platinum']),
        'is_active': random.choice([True, False])
    }

@pytest.fixture
def sample_transaction_data():
    """Generate sample transaction data for testing"""
    return {
        'transaction_id': fake.uuid4(),
        'user_id': fake.uuid4(),
        'product_id': fake.uuid4(),
        'quantity': random.randint(1, 5),
        'unit_price': round(random.uniform(10, 500), 2),
        'total_amount': 0,  # Will be calculated
        'status': random.choice(['pending', 'completed', 'failed']),
        'created_at': fake.date_time_between(start_date='-30d', end_date='now')
    }

@pytest.fixture
def database_with_sample_data(sample_user_data, sample_transaction_data):
    """Set up test database with sample data"""
    # Setup test database
    test_db = create_test_database()
    
    # Insert sample data
    test_db.insert_user(sample_user_data)
    test_db.insert_transaction(sample_transaction_data)
    
    yield test_db
    
    # Cleanup
    test_db.cleanup()
```

## Integration Testing

### Database Integration Tests
```python
# tests/integration/test_database_integration.py
import pytest
import psycopg2
from testcontainers.postgres import PostgresContainer

class TestDatabaseIntegration:
    """Integration tests for database operations"""
    
    @pytest.fixture(scope="class")
    def postgres_container(self):
        """Start PostgreSQL container for testing"""
        with PostgresContainer("postgres:15") as postgres:
            # Initialize schema
            connection = psycopg2.connect(postgres.get_connection_url())
            cursor = connection.cursor()
            
            # Load schema
            with open('docker/postgres/init/01-init-database.sql', 'r') as f:
                cursor.execute(f.read())
            
            connection.commit()
            yield postgres
    
    def test_user_crud_operations(self, postgres_container):
        """Test user CRUD operations"""
        connection = psycopg2.connect(postgres_container.get_connection_url())
        cursor = connection.cursor()
        
        # Create user
        user_data = {
            'user_id': 'test-user-123',
            'email': 'test@example.com',
            'first_name': 'Test',
            'last_name': 'User'
        }
        
        cursor.execute("""
            INSERT INTO users (user_id, email, first_name, last_name)
            VALUES (%(user_id)s, %(email)s, %(first_name)s, %(last_name)s)
        """, user_data)
        
        # Read user
        cursor.execute("SELECT * FROM users WHERE user_id = %s", (user_data['user_id'],))
        result = cursor.fetchone()
        
        assert result is not None
        assert result[1] == user_data['email']  # email column
        
        connection.commit()
        connection.close()
    
    def test_transaction_referential_integrity(self, postgres_container):
        """Test foreign key constraints"""
        connection = psycopg2.connect(postgres_container.get_connection_url())
        cursor = connection.cursor()
        
        # Try to insert transaction with non-existent user
        with pytest.raises(psycopg2.IntegrityError):
            cursor.execute("""
                INSERT INTO transactions (transaction_id, user_id, product_id, quantity, unit_price, total_amount)
                VALUES ('tx-123', 'non-existent-user', 'prod-123', 1, 10.00, 10.00)
            """)
        
        connection.rollback()
        connection.close()
```

### API Integration Tests
```python
# tests/integration/test_api_integration.py
import pytest
import requests
from testcontainers.compose import DockerCompose

class TestAPIIntegration:
    """Integration tests for API endpoints"""
    
    @pytest.fixture(scope="class")
    def api_service(self):
        """Start API service with dependencies"""
        with DockerCompose(".", compose_file_name="docker-compose.test.yml") as compose:
            # Wait for services to be ready
            api_url = f"http://localhost:{compose.get_service_port('api', 8000)}"
            
            # Health check
            for _ in range(30):  # Wait up to 30 seconds
                try:
                    response = requests.get(f"{api_url}/health")
                    if response.status_code == 200:
                        break
                except requests.ConnectionError:
                    pass
                time.sleep(1)
            
            yield api_url
    
    def test_user_api_endpoints(self, api_service):
        """Test user API CRUD operations"""
        base_url = api_service
        
        # Create user
        user_data = {
            'email': 'test@example.com',
            'first_name': 'Test',
            'last_name': 'User'
        }
        
        response = requests.post(f"{base_url}/users", json=user_data)
        assert response.status_code == 201
        
        user_id = response.json()['user_id']
        
        # Get user
        response = requests.get(f"{base_url}/users/{user_id}")
        assert response.status_code == 200
        assert response.json()['email'] == user_data['email']
        
        # Update user
        update_data = {'first_name': 'Updated'}
        response = requests.patch(f"{base_url}/users/{user_id}", json=update_data)
        assert response.status_code == 200
        
        # Delete user
        response = requests.delete(f"{base_url}/users/{user_id}")
        assert response.status_code == 204
```

## End-to-End Testing

### Pipeline E2E Tests
```python
# tests/e2e/test_pipeline_e2e.py
import pytest
from airflow.models import DagBag
from airflow.utils.state import State
import time

class TestPipelineE2E:
    """End-to-end pipeline testing"""
    
    @pytest.fixture(scope="class")
    def dag_bag(self):
        """Load DAG bag for testing"""
        return DagBag(dag_folder='airflow/dags', include_examples=False)
    
    def test_data_pipeline_main_dag_structure(self, dag_bag):
        """Test DAG structure and dependencies"""
        dag = dag_bag.get_dag('data_pipeline_main')
        
        assert dag is not None
        assert len(dag.tasks) > 0
        
        # Check for required tasks
        task_ids = [task.task_id for task in dag.tasks]
        required_tasks = [
            'start_pipeline',
            'check_data_freshness',
            'extract_and_validate_data',
            'run_dbt_models',
            'update_clickhouse_realtime',
            'end_pipeline'
        ]
        
        for required_task in required_tasks:
            assert required_task in task_ids, f"Required task {required_task} not found"
    
    def test_full_pipeline_execution(self, dag_bag):
        """Test complete pipeline execution"""
        dag = dag_bag.get_dag('data_pipeline_main')
        
        # Create DAG run
        dag_run = dag.create_dagrun(
            run_id=f"test_run_{int(time.time())}",
            state=State.RUNNING,
            execution_date=datetime.now(),
            start_date=datetime.now()
        )
        
        # Execute DAG
        for task in dag.topological_sort():
            task_instance = dag_run.get_task_instance(task.task_id)
            task_instance.run(ignore_dependencies=True)
            
            # Check task succeeded
            assert task_instance.state == State.SUCCESS, f"Task {task.task_id} failed"
        
        # Verify final state
        assert dag_run.state == State.SUCCESS
    
    def test_data_quality_after_pipeline(self):
        """Test data quality after pipeline execution"""
        # Connect to database
        connection = get_database_connection()
        
        # Check data quality metrics
        quality_checks = {
            'user_count': "SELECT COUNT(*) FROM marts.dim_users",
            'transaction_count': "SELECT COUNT(*) FROM marts.fact_transactions",
            'revenue_total': "SELECT SUM(total_revenue) FROM marts.dim_users"
        }
        
        results = {}
        for check_name, query in quality_checks.items():
            cursor = connection.cursor()
            cursor.execute(query)
            results[check_name] = cursor.fetchone()[0]
        
        # Assertions
        assert results['user_count'] > 0, "No users found after pipeline"
        assert results['transaction_count'] > 0, "No transactions found after pipeline"
        assert results['revenue_total'] > 0, "No revenue calculated after pipeline"
```

## Performance Testing

### Load Testing
```python
# tests/performance/test_load_performance.py
import pytest
import time
import concurrent.futures
from statistics import mean, median

class TestLoadPerformance:
    """Performance and load testing"""
    
    def test_data_processing_performance(self):
        """Test data processing performance under load"""
        processor = DataProcessor()
        
        # Generate test data
        test_data = [generate_sample_data() for _ in range(1000)]
        
        # Measure processing time
        start_time = time.time()
        results = processor.process_batch(test_data)
        end_time = time.time()
        
        processing_time = end_time - start_time
        throughput = len(test_data) / processing_time
        
        # Performance assertions
        assert processing_time < 30, f"Processing took {processing_time}s, expected < 30s"
        assert throughput > 30, f"Throughput {throughput} records/s, expected > 30"
        assert len(results) == len(test_data), "Not all records processed"
    
    def test_concurrent_api_requests(self):
        """Test API performance under concurrent load"""
        api_url = "http://localhost:8000"
        num_requests = 100
        concurrent_users = 10
        
        def make_request():
            response = requests.get(f"{api_url}/users")
            return response.status_code, response.elapsed.total_seconds()
        
        # Execute concurrent requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_users) as executor:
            futures = [executor.submit(make_request) for _ in range(num_requests)]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]
        
        # Analyze results
        status_codes = [result[0] for result in results]
        response_times = [result[1] for result in results]
        
        # Performance assertions
        success_rate = sum(1 for code in status_codes if code == 200) / len(status_codes)
        avg_response_time = mean(response_times)
        p95_response_time = sorted(response_times)[int(0.95 * len(response_times))]
        
        assert success_rate >= 0.95, f"Success rate {success_rate}, expected >= 0.95"
        assert avg_response_time < 1.0, f"Average response time {avg_response_time}s, expected < 1.0s"
        assert p95_response_time < 2.0, f"P95 response time {p95_response_time}s, expected < 2.0s"
```

## Test Configuration and Setup

### pytest Configuration
```ini
# pytest.ini
[tool:pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = 
    --verbose
    --tb=short
    --strict-markers
    --disable-warnings
    --cov=src
    --cov-report=html
    --cov-report=term-missing
    --cov-fail-under=80

markers =
    unit: Unit tests
    integration: Integration tests
    e2e: End-to-end tests
    performance: Performance tests
    slow: Slow running tests
    database: Tests requiring database
```

### Test Environment Setup
```python
# conftest.py
import pytest
import os
from unittest.mock import Mock

@pytest.fixture(scope="session", autouse=True)
def setup_test_environment():
    """Set up test environment variables"""
    os.environ.update({
        'ENVIRONMENT': 'test',
        'DATABASE_URL': 'postgresql://test:test@localhost:5432/test_db',
        'REDIS_URL': 'redis://localhost:6379/1',
        'LOG_LEVEL': 'DEBUG'
    })

@pytest.fixture
def mock_database():
    """Mock database for unit tests"""
    mock_db = Mock()
    mock_db.query.return_value = []
    mock_db.insert.return_value = True
    mock_db.update.return_value = True
    mock_db.delete.return_value = True
    return mock_db

@pytest.fixture
def mock_external_api():
    """Mock external API calls"""
    mock_api = Mock()
    mock_api.get.return_value.status_code = 200
    mock_api.get.return_value.json.return_value = {'status': 'success'}
    return mock_api
```