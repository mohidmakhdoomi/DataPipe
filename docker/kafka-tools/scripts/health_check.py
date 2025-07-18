#!/usr/bin/env python3
"""
Health check script for Kafka tools container
"""

import os
import sys
from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError

def check_kafka_connection():
    """Check if we can connect to Kafka"""
    try:
        bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
        
        # Try to create a producer
        producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: str(v).encode('utf-8'),
            request_timeout_ms=5000
        )
        
        # Test connection by sending a test message
        future = producer.send('__test_topic__', value='health_check')
        producer.flush(timeout=5)
        producer.close()
        
        print(f"✅ Kafka connection successful to {bootstrap_servers}")
        return True
        
    except Exception as e:
        print(f"❌ Kafka connection failed: {e}")
        return False

if __name__ == "__main__":
    if check_kafka_connection():
        sys.exit(0)
    else:
        sys.exit(1)