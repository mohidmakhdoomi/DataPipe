#!/usr/bin/env python3
"""
Main script to stream generated data to Kafka topics
"""

import os
import sys
import time
import json
import logging
from datetime import datetime
from kafka import KafkaProducer
from kafka.errors import KafkaError

# Add parent directory to path to import data generator
sys.path.append('/app')
sys.path.append('/app/producers')

from data_producer import DataProducer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def main():
    """Main streaming function"""
    logger.info("🚀 Starting data streaming service...")
    
    # Configuration
    bootstrap_servers = os.getenv('KAFKA_BOOTSTRAP_SERVERS', 'kafka:9092')
    batch_size = int(os.getenv('BATCH_SIZE', '100'))
    interval_seconds = int(os.getenv('INTERVAL_SECONDS', '60'))
    
    # Initialize data producer
    producer = DataProducer(bootstrap_servers=bootstrap_servers)
    
    try:
        while True:
            logger.info(f"📊 Generating and streaming {batch_size} events...")
            
            # Generate and stream user events
            events_sent = producer.stream_user_events(batch_size)
            logger.info(f"✅ Sent {events_sent} user events")
            
            # Generate and stream transactions
            transactions_sent = producer.stream_transactions(batch_size // 10)  # Fewer transactions
            logger.info(f"✅ Sent {transactions_sent} transactions")
            
            logger.info(f"😴 Sleeping for {interval_seconds} seconds...")
            time.sleep(interval_seconds)
            
    except KeyboardInterrupt:
        logger.info("🛑 Stopping data streaming service...")
    except Exception as e:
        logger.error(f"❌ Error in streaming service: {e}")
        raise
    finally:
        producer.close()
        logger.info("👋 Data streaming service stopped")

if __name__ == "__main__":
    main()