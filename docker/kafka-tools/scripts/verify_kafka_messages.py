#!/usr/bin/env python3
"""
Verify Kafka message delivery with synchronous confirmation
"""
import json
import time
from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError

def test_kafka_roundtrip():
    """Test sending and receiving messages to verify Kafka is working"""
    print("🧪 Testing Kafka message roundtrip...")
    
    try:
        # Producer with synchronous delivery
        producer = KafkaProducer(
            bootstrap_servers=['kafka:29092'],
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks='all',  # Wait for all replicas
            retries=3,
            batch_size=1,
            linger_ms=0,
            request_timeout_ms=10000
        )
        print("✅ Producer connected")
        
        # Send test message with synchronous confirmation
        test_message = {
            'id': 'test-123',
            'message': 'verification_test',
            'timestamp': time.time()
        }
        
        print("📤 Sending test message...")
        future = producer.send('user_events', value=test_message)
        
        # Wait for confirmation
        record_metadata = future.get(timeout=10)
        print(f"✅ Message confirmed: partition={record_metadata.partition}, offset={record_metadata.offset}")
        
        producer.close()
        
        # Now try to consume the message
        print("📥 Attempting to consume message...")
        consumer = KafkaConsumer(
            'user_events',
            bootstrap_servers=['kafka:29092'],
            value_deserializer=lambda m: json.loads(m.decode('utf-8')),
            auto_offset_reset='earliest',
            consumer_timeout_ms=5000
        )
        
        message_found = False
        for message in consumer:
            if message.value.get('id') == 'test-123':
                print(f"✅ Received message: {message.value}")
                message_found = True
                break
        
        consumer.close()
        
        if message_found:
            print("🎉 Kafka roundtrip test PASSED!")
            return True
        else:
            print("❌ Message not found in consumer")
            return False
            
    except Exception as e:
        print(f"❌ Kafka test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_kafka_roundtrip()
    exit(0 if success else 1)