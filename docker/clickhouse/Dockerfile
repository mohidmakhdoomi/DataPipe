FROM clickhouse/clickhouse-server:23.12

LABEL description="ClickHouse for real-time analytics"

# Copy custom configuration
COPY config/config.xml /etc/clickhouse-server/config.d/
COPY config/users.xml /etc/clickhouse-server/users.d/

# Copy initialization scripts
COPY init-scripts/ /docker-entrypoint-initdb.d/

# Set environment variables
ENV CLICKHOUSE_DB=analytics
ENV CLICKHOUSE_USER=analytics_user
ENV CLICKHOUSE_PASSWORD=analytics_password

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD clickhouse-client --query "SELECT 1" || exit 1

# Expose ports
EXPOSE 8123 9000 9009