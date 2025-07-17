FROM data-pipeline/base:latest

LABEL description="Kafka tools for data streaming"

# Install Kafka Python client and additional tools
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Copy Kafka tools and scripts
COPY --chown=appuser:appuser scripts/ /app/scripts/
COPY --chown=appuser:appuser producers/ /app/producers/
COPY --chown=appuser:appuser consumers/ /app/consumers/

# Make scripts executable
RUN chmod +x /app/scripts/*.py

# Set environment variables
ENV KAFKA_BOOTSTRAP_SERVERS=kafka:9092
ENV PYTHONPATH=/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python /app/scripts/health_check.py || exit 1

# Default command
CMD ["python", "/app/scripts/stream_data.py"]