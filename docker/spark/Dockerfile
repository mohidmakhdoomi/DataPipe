FROM bitnami/spark:3.5

LABEL description="Spark jobs container for data pipeline ETL processing"

USER root

# Install additional Python packages for data processing
COPY docker/spark/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Install AWS CLI for S3 operations
RUN apt-get update && apt-get install -y \
    awscli \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Add Hadoop AWS JARs for S3 connectivity
RUN curl -o /opt/bitnami/spark/jars/hadoop-aws-3.3.4.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar && \
    curl -o /opt/bitnami/spark/jars/aws-java-sdk-bundle-1.12.367.jar \
    https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.367/aws-java-sdk-bundle-1.12.367.jar

# Create application directory
RUN mkdir -p /app/jobs /app/config /app/libs
COPY --chown=1001:1001 docker/spark/spark-jobs/ /app/jobs/

# Set working directory
WORKDIR /app

# Switch back to spark user
USER 1001

# Set environment variables
ENV SPARK_HOME=/opt/bitnami/spark
ENV PYTHONPATH=/app:$PYTHONPATH
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import pyspark; print('Spark available')" || exit 1

# Default command (can be overridden)
CMD ["python", "/app/jobs/etl_job.py"]