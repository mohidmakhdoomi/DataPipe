"""
Kafka producer for streaming generated data
"""

import json
import logging
import random
from datetime import datetime
from typing import List
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Import our data generator (assuming it's available)
try:
    from generator import DataGenerator
except ImportError:
    # Fallback for testing
    class DataGenerator:
        def __init__(self):
            pass
        def generate_user_events(self, days=1, events_per_day=100):
            return []
        def generate_transactions(self, days=1):
            return []

logger = logging.getLogger(__name__)

class DataProducer:
    """Kafka producer for streaming data pipeline events"""
    
    def __init__(self, bootstrap_servers='kafka:9092'):
        self.bootstrap_servers = bootstrap_servers
        self.producer = None
        self.data_generator = DataGenerator()
        self._connect()
    
    def _connect(self):
        """Initialize Kafka producer"""
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=self.bootstrap_servers,
                value_serializer=lambda v: json.dumps(v, default=str).encode('utf-8'),
                key_serializer=lambda k: str(k).encode('utf-8') if k else None,
                acks='all',
                retries=3,
                batch_size=16384,
                linger_ms=10,
                buffer_memory=33554432,
                compression_type='gzip'
            )
            logger.info(f"✅ Connected to Kafka at {self.bootstrap_servers}")
        except Exception as e:
            logger.error(f"❌ Failed to connect to Kafka: {e}")
            raise
    
    def stream_user_events(self, count: int = 100) -> int:
        """Stream user events to Kafka"""
        try:
            # Generate some users and products first if not already done
            if not hasattr(self.data_generator, 'users') or not self.data_generator.users:
                self.data_generator.generate_users(100)
            if not hasattr(self.data_generator, 'products') or not self.data_generator.products:
                self.data_generator.generate_products(50)
            
            # Generate events
            events = self.data_generator.generate_user_events(days=1, events_per_day=count)
            
            sent_count = 0
            for event in events:
                try:
                    # Convert to dict for JSON serialization
                    event_data = event.model_dump()
                    
                    # Send to Kafka
                    future = self.producer.send(
                        'user_events',
                        key=event.user_id,
                        value=event_data
                    )
                    
                    # Optional: wait for confirmation (can be removed for better performance)
                    # future.get(timeout=10)
                    sent_count += 1
                    
                except Exception as e:
                    logger.error(f"Failed to send event {event.event_id}: {e}")
            
            # Flush to ensure all messages are sent
            self.producer.flush()
            return sent_count
            
        except Exception as e:
            logger.error(f"Error streaming user events: {e}")
            return 0
    
    def stream_transactions(self, count: int = 10) -> int:
        """Stream transactions to Kafka"""
        try:
            # Generate transactions
            transactions = self.data_generator.generate_transactions(days=1)
            
            # Limit to requested count
            transactions = transactions[:count] if len(transactions) > count else transactions
            
            sent_count = 0
            for transaction in transactions:
                try:
                    # Convert to dict for JSON serialization
                    transaction_data = transaction.model_dump()
                    
                    # Send to Kafka
                    future = self.producer.send(
                        'transactions',
                        key=transaction.user_id,
                        value=transaction_data
                    )
                    
                    sent_count += 1
                    
                except Exception as e:
                    logger.error(f"Failed to send transaction {transaction.transaction_id}: {e}")
            
            # Flush to ensure all messages are sent
            self.producer.flush()
            return sent_count
            
        except Exception as e:
            logger.error(f"Error streaming transactions: {e}")
            return 0
    
    def send_custom_event(self, topic: str, key: str, value: dict):
        """Send a custom event to specified topic"""
        try:
            future = self.producer.send(topic, key=key, value=value)
            future.get(timeout=10)
            logger.info(f"Sent custom event to {topic}")
        except Exception as e:
            logger.error(f"Failed to send custom event: {e}")
            raise
    
    def close(self):
        """Close the producer"""
        if self.producer:
            self.producer.close()
            logger.info("Kafka producer closed")