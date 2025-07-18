from pydantic import BaseModel
from typing import Optional
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class Settings(BaseModel):
    # Database settings
    postgres_host: str = os.getenv("POSTGRES_HOST", "127.0.0.1")
    postgres_port: int = int(os.getenv("POSTGRES_PORT", "5432"))
    postgres_db: str = os.getenv("POSTGRES_DB", "transactions_db")
    postgres_user: str = os.getenv("POSTGRES_USER", "postgres")
    postgres_password: str = os.getenv("POSTGRES_PASSWORD", "")
    
    # Kafka settings
    kafka_bootstrap_servers: str = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
    kafka_topic_events: str = os.getenv("KAFKA_TOPIC_EVENTS", "user_events")
    kafka_topic_transactions: str = os.getenv("KAFKA_TOPIC_TRANSACTIONS", "transactions")
    
    # Data generation settings
    num_users: int = int(os.getenv("NUM_USERS", "10000"))
    num_products: int = int(os.getenv("NUM_PRODUCTS", "1000"))
    days_of_data: int = int(os.getenv("DAYS_OF_DATA", "90"))
    events_per_day: int = int(os.getenv("EVENTS_PER_DAY", "50000"))

settings = Settings()