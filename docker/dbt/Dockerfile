FROM data-pipeline/base:latest

LABEL description="dbt service for data transformations"

# Install dbt and database adapters
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Create dbt project directory
RUN mkdir -p /app/dbt_project && chown appuser:appuser /app/dbt_project

# Copy dbt project files
COPY --chown=appuser:appuser dbt_project/ /app/dbt_project/

# Set dbt profiles directory
ENV DBT_PROFILES_DIR=/app/dbt_project/profiles

WORKDIR /app/dbt_project

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD dbt --version || exit 1

# Default command
CMD ["dbt", "run"]