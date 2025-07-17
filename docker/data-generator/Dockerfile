FROM data-pipeline/base:latest

LABEL description="Data generator service for realistic transaction data"

# Install additional dependencies for data generation
USER root
COPY docker/data-generator/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt
USER appuser

# Copy data generator code
COPY --chown=appuser:appuser data-generators/ /app/

# Create output directory
RUN mkdir -p /app/output && chown appuser:appuser /app/output

# Set environment variables
ENV PYTHONPATH=/app
ENV OUTPUT_DIR=/app/output

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import generator; print('OK')" || exit 1

# Default command
CMD ["python", "generator.py", "--output", "/app/output"]