FROM apache/airflow:2.8.0-python3.11

USER root

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Install additional Python packages
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Copy DAGs, plugins, and config
COPY --chown=airflow:root dags/ /opt/airflow/dags/
COPY --chown=airflow:root plugins/ /opt/airflow/plugins/
COPY --chown=airflow:root config/ /opt/airflow/config/

# Copy dbt project for transformations
COPY --chown=airflow:root ../../dbt/ /opt/airflow/dbt/

# Set environment variables
ENV AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=false
ENV AIRFLOW__CORE__LOAD_EXAMPLES=false
ENV AIRFLOW__WEBSERVER__EXPOSE_CONFIG=true
ENV AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL=30
ENV AIRFLOW__CORE__PARALLELISM=32
ENV AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG=16

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD airflow jobs check --job-type SchedulerJob --hostname "$${HOSTNAME}"