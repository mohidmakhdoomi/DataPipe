FROM data-pipeline/base:latest

LABEL description="Kafka tools for data streaming"

# Install Kafka Python client and additional tools
USER root
COPY docker/kafka-tools/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt
USER appuser

# Copy Kafka tools and scripts
COPY --chown=appuser:appuser docker/kafka-tools/scripts/ /app/scripts/
COPY --chown=appuser:appuser docker/kafka-tools/producers/ /app/producers/

# Create consumers directory (for future use)
RUN mkdir -p /app/consumers && chown appuser:appuser /app/consumers

# Make scripts executable
RUN chmod +x /app/scripts/*.py

# Set environment variables
ENV KAFKA_BOOTSTRAP_SERVERS=kafka:29092
ENV PYTHONPATH=/app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python /app/scripts/health_check.py || exit 1

# Default command
CMD ["python", "/app/scripts/stream_data.py"]