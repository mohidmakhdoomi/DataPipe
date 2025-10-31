# Custom Spark Docker Image with S3 and Iceberg Support
# Based on official Spark 3.5.7 image with jars for hadoop-aws + dependencies and iceberg

FROM apache/spark:3.5.7-scala2.12-java11-python3-ubuntu

WORKDIR /

USER root

ENV HADOOP_AWS_NAME=hadoop-aws
ENV HADOOP_AWS_VERSION=3.3.4
ENV AWS_BUNDLE_NAME=aws-java-sdk-bundle
ENV AWS_BUNDLE_VERSION=1.12.262
ENV WILDFLY_SSL_NAME=wildfly-openssl
ENV WILDFLY_SSL_VERSION=1.0.7.Final

ENV ICEBERG_NAME=iceberg-spark-runtime-3.5_2.12
ENV ICEBERG_VERSION=1.10.0

ENV SNOWFLAKE_NAME=spark-snowflake_2.12
ENV SNOWFLAKE_VERSION=3.1.5
ENV SNOWFLAKE_JDBC_NAME=snowflake-jdbc
ENV SNOWFLAKE_JDBC_VERSION=3.24.2
ENV PARQUET_NAME=parquet-avro
ENV PARQUET_VERSION=1.15.2

RUN set -ex; \
    export SPARK_TMP="$(mktemp -d)"; \
    cd $SPARK_TMP; \
    curl -L -o ${HADOOP_AWS_NAME}-${HADOOP_AWS_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/${HADOOP_AWS_NAME}/${HADOOP_AWS_VERSION}/${HADOOP_AWS_NAME}-${HADOOP_AWS_VERSION}.jar; \
    curl -L -o ${AWS_BUNDLE_NAME}-${AWS_BUNDLE_VERSION}.jar \
    https://repo1.maven.org/maven2/com/amazonaws/${AWS_BUNDLE_NAME}/${AWS_BUNDLE_VERSION}/${AWS_BUNDLE_NAME}-${AWS_BUNDLE_VERSION}.jar; \
    curl -L -o ${WILDFLY_SSL_NAME}-${WILDFLY_SSL_VERSION}.jar \
    https://repo1.maven.org/maven2/org/wildfly/openssl/${WILDFLY_SSL_NAME}/${WILDFLY_SSL_VERSION}/${WILDFLY_SSL_NAME}-${WILDFLY_SSL_VERSION}.jar; \
    curl -L -o ${ICEBERG_NAME}-${ICEBERG_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/${ICEBERG_NAME}/${ICEBERG_VERSION}/${ICEBERG_NAME}-${ICEBERG_VERSION}.jar; \
    curl -L -o ${SNOWFLAKE_NAME}-${SNOWFLAKE_VERSION}.jar \
    https://repo1.maven.org/maven2/net/snowflake/${SNOWFLAKE_NAME}/${SNOWFLAKE_VERSION}/${SNOWFLAKE_NAME}-${SNOWFLAKE_VERSION}.jar; \
    curl -L -o ${SNOWFLAKE_JDBC_NAME}-${SNOWFLAKE_JDBC_VERSION}.jar \
    https://repo1.maven.org/maven2/net/snowflake/${SNOWFLAKE_JDBC_NAME}/${SNOWFLAKE_JDBC_VERSION}/${SNOWFLAKE_JDBC_NAME}-${SNOWFLAKE_JDBC_VERSION}.jar; \
    curl -L -o ${PARQUET_NAME}-${PARQUET_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/parquet/${PARQUET_NAME}/${PARQUET_VERSION}/${PARQUET_NAME}-${PARQUET_VERSION}.jar; \
    chown -R spark:spark .; \
    cp * /opt/spark/jars/; \
    cd ..; \
    rm -rf "$SPARK_TMP";

# Verify jars were downloaded successfully
RUN ls -la /opt/spark/jars/${HADOOP_AWS_NAME}* /opt/spark/jars/${AWS_BUNDLE_NAME}* /opt/spark/jars/${WILDFLY_SSL_NAME}*
RUN ls -la /opt/spark/jars/${ICEBERG_NAME}*
RUN ls -la /opt/spark/jars/${SNOWFLAKE_NAME}* /opt/spark/jars/${SNOWFLAKE_JDBC_NAME}* /opt/spark/jars/${PARQUET_NAME}*

WORKDIR /opt/spark/work-dir

USER spark

ENTRYPOINT [ "/opt/entrypoint.sh" ]