# Custom Spark Docker Image with S3 and Iceberg Support
# Based on official Spark 4.0.0 image with pre-installed jars for hadoop-aws + dependencies and iceberg

FROM apache/spark:4.0.1-scala2.13-java17-python3-ubuntu

WORKDIR /

USER root

ENV AWS_BUNDLE_NAME=bundle
ENV AWS_BUNDLE_VERSION=2.24.6
# ENV AWS_ANALYTICS_NAME=analyticsaccelerator-s3 # needed for hadoop-aws 3.4.2 not 3.4.1
# ENV AWS_ANALYTICS_VERSION=1.2.1
ENV WILDFLY_SSL_NAME=wildfly-openssl
ENV WILDFLY_SSL_VERSION=1.1.3.Final
ENV HADOOP_AWS_NAME=hadoop-aws
ENV HADOOP_AWS_VERSION=3.4.1
ENV ICEBERG_NAME=iceberg-spark-runtime-4.0_2.13
ENV ICEBERG_VERSION=1.10.0

RUN set -ex; \
    export SPARK_TMP="$(mktemp -d)"; \
    cd $SPARK_TMP; \
    curl -L -o ${AWS_BUNDLE_NAME}-${AWS_BUNDLE_VERSION}.jar \
    https://repo1.maven.org/maven2/software/amazon/awssdk/${AWS_BUNDLE_NAME}/${AWS_BUNDLE_VERSION}/${AWS_BUNDLE_NAME}-${AWS_BUNDLE_VERSION}.jar; \
    # curl -L -o ${AWS_ANALYTICS_NAME}-${AWS_ANALYTICS_VERSION}.jar \
    # https://repo1.maven.org/maven2/software/amazon/s3/analyticsaccelerator/${AWS_ANALYTICS_NAME}/${AWS_ANALYTICS_VERSION}/${AWS_ANALYTICS_NAME}-${AWS_ANALYTICS_VERSION}.jar; \
    curl -L -o ${WILDFLY_SSL_NAME}-${WILDFLY_SSL_VERSION}.jar \
    https://repo1.maven.org/maven2/org/wildfly/openssl/${WILDFLY_SSL_NAME}/${WILDFLY_SSL_VERSION}/${WILDFLY_SSL_NAME}-${WILDFLY_SSL_VERSION}.jar; \
    curl -L -o ${HADOOP_AWS_NAME}-${HADOOP_AWS_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/${HADOOP_AWS_NAME}/${HADOOP_AWS_VERSION}/${HADOOP_AWS_NAME}-${HADOOP_AWS_VERSION}.jar; \
    curl -L -o ${ICEBERG_NAME}-${ICEBERG_VERSION}.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/${ICEBERG_NAME}/${ICEBERG_VERSION}/${ICEBERG_NAME}-${ICEBERG_VERSION}.jar; \
    chown -R spark:spark .; \
    cp * /opt/spark/jars/; \
    cd ..; \
    rm -rf "$SPARK_TMP";

# Verify jars were downloaded successfully
# RUN ls -la /opt/spark/jars/${AWS_BUNDLE_NAME}* /opt/spark/jars/${AWS_ANALYTICS_NAME}*  /opt/spark/jars/${WILDFLY_SSL_NAME}* /opt/spark/jars/${HADOOP_AWS_NAME}* /opt/spark/jars/${ICEBERG_NAME}*
RUN ls -la /opt/spark/jars/${AWS_BUNDLE_NAME}* /opt/spark/jars/${WILDFLY_SSL_NAME}* /opt/spark/jars/${HADOOP_AWS_NAME}* /opt/spark/jars/${ICEBERG_NAME}*

WORKDIR /opt/spark/work-dir

USER spark

ENTRYPOINT [ "/opt/entrypoint.sh" ]