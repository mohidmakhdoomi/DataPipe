# Airflow Development Environment

This directory contains the Airflow development setup for local testing and development.

## ✅ **What's Included:**

### **Complete Local Stack:**
- **Airflow Webserver & Scheduler** - Full Airflow environment
- **PostgreSQL** - Both Airflow metadata and data pipeline databases
- **ClickHouse** - Real-time analytics database
- **Data Generator** - Continuous realistic data generation

### **Production-Ready DAGs:**
- **data_pipeline_main.py** - Core ETL orchestration
- **data_quality_monitoring.py** - Comprehensive data validation
- **data_backfill.py** - Historical data processing
- **maintenance_operations.py** - Database optimization
- **pipeline_monitoring.py** - End-to-end health monitoring

## 🚀 **Quick Start:**

### **1. Start the Environment:**
```powershell
# Copy environment file
cp .env.example .env

# Start all services
scripts\start-docker.ps1
```

### **2. Access Services:**
- **Airflow UI**: http://localhost:8080 (admin/admin)
- **PostgreSQL**: localhost:5432 (postgres/postgres_password)
- **ClickHouse**: http://localhost:8123 (analytics_user/analytics_password)

### **3. Test DAGs:**
```powershell
# Test all DAG syntax
.\scripts\test-dags.ps1

# Test specific DAG
.\scripts\test-dags.ps1 -DagId "data_pipeline_main"

# Test specific task
.\scripts\test-dags.ps1 -DagId "data_pipeline_main" -TaskId "extract_data"
```

### **4. Stop Environment:**
```powershell
scripts\stop-docker.ps1
```

## 📁 **Directory Structure:**

```
airflow/
├── dags/                           # Production DAG files
│   └── data_pipeline_main.py      # Main ETL orchestration
├── scripts/                        # Helper scripts
│   └── test-dags.ps1              # Test DAGs
├── config/                         # Airflow configuration
│   └── airflow_local_settings.py  # Custom settings
├── logs/                          # Airflow logs (auto-created)
├── plugins/                       # Custom plugins (auto-created)
├── docker-compose.yml             # Complete local stack
├── requirements.txt               # Python dependencies
└── .env.example                   # Environment template
```

## 🔧 **Development Workflow:**

### **1. DAG Development:**
```bash
# Edit DAGs in dags/ directory
# Changes are automatically picked up by Airflow

# Test syntax
python -m py_compile dags/your_dag.py

# Test in Airflow UI
# Go to http://localhost:8080 and trigger DAG
```

### **2. Local Testing:**
```bash
# Test specific task locally
docker-compose exec airflow-scheduler airflow tasks test data_pipeline_main extract_data 2024-01-01

# Check DAG structure
docker-compose exec airflow-scheduler airflow dags show data_pipeline_main
```

### **3. Database Access:**
```bash
# Connect to data PostgreSQL
psql -h localhost -p 5432 -U postgres -d transactions_db

# Connect to ClickHouse
curl "http://localhost:8123/?query=SELECT * FROM analytics.transactions LIMIT 5"
```

## 🎯 **Key Features:**

### **Enterprise DAG Patterns:**
- **Task Groups** for logical organization
- **Branching Logic** for conditional processing
- **XCom Communication** between tasks
- **Trigger Rules** for complex dependencies
- **Error Handling** with retries and alerts

### **Data Quality Integration:**
- **Automated validation** at every step
- **Statistical anomaly detection**
- **Business rule enforcement**
- **Quality scoring and reporting**

### **Monitoring & Alerting:**
- **SLA compliance tracking**
- **Performance monitoring**
- **Resource utilization checks**
- **Multi-level alerting system**

### **Production Readiness:**
- **Comprehensive error handling**
- **Detailed logging and metrics**
- **Health checks and monitoring**
- **Scalable architecture patterns**

## 🔍 **Troubleshooting:**

### **Common Issues:**

**Airflow not starting:**
```bash
# Check Docker status
docker ps

# View logs
docker-compose logs airflow-webserver
docker-compose logs airflow-scheduler
```

**DAG not appearing:**
```bash
# Check DAG syntax
python -m py_compile dags/your_dag.py

# Check import errors
docker-compose exec airflow-scheduler airflow dags list-import-errors
```

**Database connection issues:**
```bash
# Test PostgreSQL connection
docker-compose exec postgres psql -U postgres -d transactions_db -c "SELECT 1;"

# Test ClickHouse connection
curl "http://localhost:8123/ping"
```

## 📊 **Monitoring:**

### **Built-in Dashboards:**
- **Airflow UI**: DAG runs, task status, logs
- **Data Quality**: Automated quality reports
- **System Health**: Resource utilization, SLA compliance

### **Custom Metrics:**
- **Pipeline Success Rate**: >95% target
- **Data Freshness**: <60 minutes target
- **Processing Time**: <30 minutes target
- **Quality Score**: >90% target

## 🚀 **Next Steps:**

1. **Customize DAGs** for your specific use case
2. **Add more data sources** and transformations
3. **Integrate with external systems** (Slack, email, etc.)
4. **Deploy to production** Kubernetes cluster
5. **Set up CI/CD** for automated deployments

This local Airflow environment provides a complete, production-like setup for developing and testing enterprise data pipelines!