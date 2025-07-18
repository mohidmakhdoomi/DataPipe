#!/usr/bin/env python3
"""
Simple test script to verify Kafka streaming functionality
"""
import json
import time
from kafka import KafkaProducer
from kafka.errors import KafkaError

def test_kafka_streaming():
    """Test basic Kafka streaming functionality"""
    print("🧪 Testing Kafka streaming...")
    
    try:
        # Initialize producer with simple settings
        producer = KafkaProducer(
            bootstrap_servers=['kafka:9092'],
            value_serializer=lambda v: json.dumps(v).encode('utf-8'),
            acks=1,
            retries=3,
            batch_size=1,  # Send immediately
            linger_ms=0,   # No batching delay
            request_timeout_ms=10000,
            max_block_ms=2000
        )
        print("✅ Connected to Kafka")
        
        # Send test messages
        test_messages = [
            {"id": 1, "message": "Hello Kafka", "timestamp": time.time()},
            {"id": 2, "message": "Streaming test", "timestamp": time.time()},
            {"id": 3, "message": "Data pipeline", "timestamp": time.time()}
        ]
        
        success_count = 0
        for msg in test_messages:
            try:
                future = producer.send('transactions', value=msg)
                # Wait for the message to be sent
                record_metadata = future.get(timeout=5)
                print(f"✅ Sent message {msg['id']} to partition {record_metadata.partition}")
                success_count += 1
            except Exception as e:
                print(f"❌ Failed to send message {msg['id']}: {e}")
        
        producer.flush(timeout=5)
        producer.close()
        
        print(f"🎯 Successfully sent {success_count}/{len(test_messages)} messages")
        return success_count > 0
        
    except Exception as e:
        print(f"❌ Kafka test failed: {e}")
        return False

if __name__ == "__main__":
    success = test_kafka_streaming()
    exit(0 if success else 1)