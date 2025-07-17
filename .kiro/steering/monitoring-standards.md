---
inclusion: fileMatch
fileMatchPattern: '**/monitoring/*.py'
---

# Monitoring and Observability Standards

## Metrics Collection

### Application Metrics
All applications must expose metrics in Prometheus format on `/metrics` endpoint:

```python
from prometheus_client import Counter, Histogram, Gauge, start_http_server

# Standard metrics for data pipelines
pipeline_runs_total = Counter('pipeline_runs_total', 'Total pipeline runs', ['dag_id', 'status'])
pipeline_duration_seconds = Histogram('pipeline_duration_seconds', 'Pipeline execution time', ['dag_id'])
data_records_processed = Counter('data_records_processed_total', 'Records processed', ['table', 'operation'])
data_quality_score = Gauge('data_quality_score', 'Data quality score', ['table'])

# Usage in pipeline code
def run_pipeline(dag_id: str):
    start_time = time.time()
    try:
        # Pipeline execution
        result = execute_pipeline()
        pipeline_runs_total.labels(dag_id=dag_id, status='success').inc()
        data_records_processed.labels(table='users', operation='extract').inc(result.count)
        return result
    except Exception as e:
        pipeline_runs_total.labels(dag_id=dag_id, status='failure').inc()
        raise
    finally:
        duration = time.time() - start_time
        pipeline_duration_seconds.labels(dag_id=dag_id).observe(duration)
```

### Infrastructure Metrics
Monitor key infrastructure components:

```yaml
# Kubernetes metrics to monitor
- name: pod_cpu_usage
  query: rate(container_cpu_usage_seconds_total[5m])
  
- name: pod_memory_usage
  query: container_memory_working_set_bytes
  
- name: pod_restart_count
  query: kube_pod_container_status_restarts_total
  
- name: persistent_volume_usage
  query: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

### Business Metrics
Track key business indicators:

```python
# Business KPIs
revenue_processed = Counter('revenue_processed_total', 'Total revenue processed', ['currency'])
customer_segments = Gauge('customer_segments_count', 'Customer count by segment', ['segment'])
data_freshness_hours = Gauge('data_freshness_hours', 'Hours since last data update', ['source'])

# SLA metrics
sla_compliance = Gauge('sla_compliance_ratio', 'SLA compliance ratio', ['service'])
error_rate = Gauge('error_rate_percent', 'Error rate percentage', ['service'])
```

## Logging Standards

### Structured Logging
Use structured JSON logging for all applications:

```python
import logging
import json
from datetime import datetime

class StructuredLogger:
    def __init__(self, name: str):
        self.logger = logging.getLogger(name)
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter('%(message)s'))
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def log(self, level: str, message: str, **kwargs):
        log_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'level': level.upper(),
            'message': message,
            'service': 'data-pipeline',
            **kwargs
        }
        
        if level == 'error':
            self.logger.error(json.dumps(log_entry))
        elif level == 'warning':
            self.logger.warning(json.dumps(log_entry))
        else:
            self.logger.info(json.dumps(log_entry))

# Usage
logger = StructuredLogger('pipeline')
logger.log('info', 'Pipeline started', dag_id='data_pipeline_main', execution_date='2024-01-01')
logger.log('error', 'Database connection failed', error_code='DB001', retry_count=3)
```

### Log Levels and Content
- **DEBUG**: Detailed diagnostic information
- **INFO**: General operational messages
- **WARNING**: Potentially harmful situations
- **ERROR**: Error events that might still allow the application to continue
- **CRITICAL**: Serious error events that might cause the application to abort

```python
# Required fields in all log entries
required_fields = {
    'timestamp': 'ISO 8601 timestamp',
    'level': 'Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)',
    'message': 'Human-readable message',
    'service': 'Service name',
    'version': 'Application version',
    'environment': 'Environment (dev, staging, prod)'
}

# Additional context fields
context_fields = {
    'user_id': 'User identifier (if applicable)',
    'request_id': 'Request correlation ID',
    'dag_id': 'Airflow DAG identifier',
    'task_id': 'Airflow task identifier',
    'execution_date': 'Pipeline execution date'
}
```

## Alerting Rules

### Critical Alerts (Immediate Response Required)
```yaml
# Pipeline failure alert
- alert: PipelineFailure
  expr: increase(pipeline_runs_total{status="failure"}[5m]) > 0
  for: 0m
  labels:
    severity: critical
  annotations:
    summary: "Pipeline {{ $labels.dag_id }} failed"
    description: "Pipeline {{ $labels.dag_id }} has failed. Check logs immediately."

# Data freshness alert
- alert: DataFreshnessViolation
  expr: data_freshness_hours > 2
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Data freshness SLA violated for {{ $labels.source }}"
    description: "Data from {{ $labels.source }} is {{ $value }} hours old, exceeding 2-hour SLA."

# System resource alert
- alert: HighMemoryUsage
  expr: (container_memory_working_set_bytes / container_spec_memory_limit_bytes) > 0.9
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "High memory usage in {{ $labels.pod }}"
    description: "Pod {{ $labels.pod }} is using {{ $value | humanizePercentage }} of available memory."
```

### Warning Alerts (Monitor Closely)
```yaml
# Performance degradation
- alert: SlowPipelineExecution
  expr: histogram_quantile(0.95, pipeline_duration_seconds) > 3600
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Pipeline {{ $labels.dag_id }} running slowly"
    description: "95th percentile execution time is {{ $value | humanizeDuration }}"

# Data quality degradation
- alert: DataQualityDegradation
  expr: data_quality_score < 0.9
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Data quality score below threshold for {{ $labels.table }}"
    description: "Data quality score is {{ $value | humanizePercentage }}, below 90% threshold."
```

## Dashboard Standards

### Executive Dashboard
Key metrics for leadership visibility:

```yaml
# High-level KPIs
panels:
  - title: "Pipeline Success Rate"
    type: stat
    query: |
      (
        sum(rate(pipeline_runs_total{status="success"}[24h])) /
        sum(rate(pipeline_runs_total[24h]))
      ) * 100
    
  - title: "Data Freshness"
    type: gauge
    query: max(data_freshness_hours)
    thresholds:
      - value: 1
        color: green
      - value: 2
        color: yellow
      - value: 4
        color: red
    
  - title: "Revenue Processed (24h)"
    type: stat
    query: sum(increase(revenue_processed_total[24h]))
```

### Operational Dashboard
Detailed metrics for operations team:

```yaml
panels:
  - title: "Pipeline Execution Times"
    type: graph
    query: histogram_quantile(0.95, rate(pipeline_duration_seconds_bucket[5m]))
    
  - title: "Error Rate by Service"
    type: graph
    query: |
      (
        sum(rate(pipeline_runs_total{status="failure"}[5m])) by (dag_id) /
        sum(rate(pipeline_runs_total[5m])) by (dag_id)
      ) * 100
    
  - title: "Resource Utilization"
    type: graph
    queries:
      - query: rate(container_cpu_usage_seconds_total[5m])
        legend: "CPU Usage"
      - query: container_memory_working_set_bytes
        legend: "Memory Usage"
```

### Data Quality Dashboard
Focused on data health metrics:

```yaml
panels:
  - title: "Data Quality Scores"
    type: heatmap
    query: data_quality_score
    
  - title: "Record Counts by Table"
    type: graph
    query: sum(increase(data_records_processed_total[1h])) by (table)
    
  - title: "Schema Validation Failures"
    type: stat
    query: sum(increase(schema_validation_failures_total[24h]))
```

## Health Checks

### Application Health Endpoints
Every service must expose health check endpoints:

```python
from flask import Flask, jsonify
import psycopg2
import redis

app = Flask(__name__)

@app.route('/health')
def health_check():
    """Basic health check - service is running"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.utcnow().isoformat()})

@app.route('/health/ready')
def readiness_check():
    """Readiness check - service is ready to handle requests"""
    checks = {
        'database': check_database_connection(),
        'cache': check_redis_connection(),
        'external_api': check_external_dependencies()
    }
    
    all_healthy = all(checks.values())
    status_code = 200 if all_healthy else 503
    
    return jsonify({
        'status': 'ready' if all_healthy else 'not_ready',
        'checks': checks,
        'timestamp': datetime.utcnow().isoformat()
    }), status_code

@app.route('/health/live')
def liveness_check():
    """Liveness check - service should be restarted if this fails"""
    try:
        # Check critical internal state
        if not check_critical_resources():
            return jsonify({'status': 'unhealthy'}), 503
        return jsonify({'status': 'alive'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503
```

### Kubernetes Health Checks
Configure appropriate probes in Kubernetes:

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: data-pipeline
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
```

## Tracing and Debugging

### Distributed Tracing
Implement distributed tracing for complex workflows:

```python
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Configure tracing
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger-agent",
    agent_port=6831,
)

span_processor = BatchSpanProcessor(jaeger_exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

# Usage in pipeline code
def extract_data(source: str):
    with tracer.start_as_current_span("extract_data") as span:
        span.set_attribute("source", source)
        span.set_attribute("operation", "extract")
        
        try:
            data = perform_extraction(source)
            span.set_attribute("records_extracted", len(data))
            span.set_status(trace.Status(trace.StatusCode.OK))
            return data
        except Exception as e:
            span.set_status(trace.Status(trace.StatusCode.ERROR, str(e)))
            span.record_exception(e)
            raise
```

### Performance Profiling
Enable profiling for performance analysis:

```python
import cProfile
import pstats
from functools import wraps

def profile_performance(func):
    """Decorator to profile function performance"""
    @wraps(func)
    def wrapper(*args, **kwargs):
        profiler = cProfile.Profile()
        profiler.enable()
        
        try:
            result = func(*args, **kwargs)
            return result
        finally:
            profiler.disable()
            stats = pstats.Stats(profiler)
            stats.sort_stats('cumulative')
            
            # Log top 10 functions by cumulative time
            stats.print_stats(10)
    
    return wrapper

# Usage
@profile_performance
def heavy_data_processing():
    # Complex data processing logic
    pass
```