My goal is to incorporate all the technologies listed, to create a data pipeline. 
Technologies:
- PostgreSQL
- Kafka
- AWS S3
- Iceberg
- Spark
- dbt core
- Snowflake
- ClickHouse
- Airflow
- Docker
- Kubernetes

Each technology should be used and careful planning should go into designing the software architecture of the data pipeline.

Use Lambda Architecture for data processing and be able to handle 10000 events per second.

Designed to keep things simple, preferring out of the box solutions and only coding custom things when needed.

Handle batch, streaming as well as change data capture. It should include real time analytics as well as business intelligence and reporting.

Purely for local deployment and I will be developing and running locally with Docker Desktop on Windows and using Kubernetes on Docker Desktop with the 'kind' provisioner and the 'containerd' image store.

Use a maximum 24GB RAM, 10 CPU cores and 1TB storage.

Airflow DAGs should be separated so that the DAGs are not in the Airflow services Docker image. However when the Airflow services are running in Docker, the DAGs should be available to them. The purpose is that whenever Airflow DAGs are updated and redeployed, the Airflow services container does not need to restarted.

PostgreSQL, Kafka, ClickHouse should run with Docker and Kubernetes but should use external storage/persistent volumes.

Snowflake, AWS S3 are real cloud services that will be connected to and will not emulated locally.

Should run Spark on Kubernetes instead of standalone.

Choosing a BI/reporting tool is out of scope and observability/logging tools are out of scope.
