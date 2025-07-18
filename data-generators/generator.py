import random
import uuid
import json
import time
from datetime import datetime, timedelta
from typing import List, Dict, Optional
import pandas as pd
from faker import Faker
from kafka import KafkaProducer
from kafka.errors import KafkaError
from models import User, Product, Transaction, UserEvent, UserTier, TransactionStatus, EventType
from config import settings

fake = Faker()

class KafkaStreamer:
    """Handles streaming data to Kafka topics"""
    
    def __init__(self):
        self.producer = None
        self._initialize_producer()
    
    def _initialize_producer(self):
        """Initialize Kafka producer with error handling"""
        try:
            self.producer = KafkaProducer(
                bootstrap_servers=settings.kafka_bootstrap_servers,
                value_serializer=lambda v: json.dumps(v, default=str).encode('utf-8'),
                key_serializer=lambda k: str(k).encode('utf-8') if k else None,
                acks='all',  # Wait for leader acknowledgment only
                retries=3,
                batch_size=1024,  # Very small batch size for immediate sending
                linger_ms=0,  # No lingering - send immediately
                buffer_memory=33554432,
                request_timeout_ms=30000,  # 30 second timeout
                max_block_ms=5000  # 5 second max block time
            )
            print(f"✅ Connected to Kafka at {settings.kafka_bootstrap_servers}")
        except Exception as e:
            print(f"❌ Failed to connect to Kafka: {e}")
            self.producer = None
    
    def stream_event(self, topic: str, event_data: dict, key: str = None):
        """Stream a single event to Kafka topic"""
        if not self.producer:
            return False
            
        try:
            # Add metadata
            event_data['_timestamp'] = datetime.now().isoformat()
            event_data['_source'] = 'data-generator'
            
            # Fire and forget - don't wait for response
            self.producer.send(
                topic=topic,
                value=event_data,
                key=key
            )
            return True
            
        except Exception as e:
            print(f"❌ Error streaming to {topic}: {e}")
            return False
    
    def stream_batch(self, topic: str, events: List[dict], key_field: str = None):
        """Stream a batch of events to Kafka topic"""
        if not self.producer:
            print(f"❌ Kafka producer not available for batch streaming to {topic}")
            return 0
            
        success_count = 0
        for event in events:
            key = event.get(key_field) if key_field else None
            if self.stream_event(topic, event, key):
                success_count += 1
                
        # Flush without timeout to avoid blocking
        try:
            self.producer.flush(timeout=1)
        except:
            pass  # Ignore flush timeouts
        return success_count
    
    def _on_send_error(self, excp):
        """Handle send errors"""
        print(f"❌ Kafka send error: {excp}")
    
    def close(self):
        """Close Kafka producer"""
        if self.producer:
            self.producer.close()

class DataGenerator:
    def __init__(self, enable_streaming: bool = False):
        self.users: List[User] = []
        self.products: List[Product] = []
        self.user_sessions: Dict[str, List[str]] = {}  # user_id -> session_ids
        self.kafka_streamer = KafkaStreamer() if enable_streaming else None
        
    def generate_users(self, count: int = None) -> List[User]:
        """Generate realistic user profiles with weighted tiers"""
        count = count or settings.num_users
        users = []
        
        # Tier distribution (realistic for most platforms)
        tier_weights = {
            UserTier.BRONZE: 0.6,
            UserTier.SILVER: 0.25, 
            UserTier.GOLD: 0.12,
            UserTier.PLATINUM: 0.03
        }
        
        for _ in range(count):
            reg_date = fake.date_time_between(start_date='-2y', end_date='now')
            tier = random.choices(
                list(tier_weights.keys()), 
                weights=list(tier_weights.values())
            )[0]
            
            # Higher tier users are more likely to be active
            is_active = random.random() < (0.7 + 0.1 * list(UserTier).index(tier))
            
            user = User(
                user_id=str(uuid.uuid4()),
                email=fake.email(),
                first_name=fake.first_name(),
                last_name=fake.last_name(),
                date_of_birth=fake.date_of_birth(minimum_age=18, maximum_age=80),
                registration_date=reg_date,
                country=fake.country(),
                city=fake.city(),
                tier=tier,
                is_active=is_active,
                last_login=fake.date_time_between(
                    start_date=reg_date, end_date='now'
                ) if is_active else None
            )
            users.append(user)
            
        self.users = users
        return users
    
    def generate_products(self, count: int = None) -> List[Product]:
        """Generate product catalog with realistic categories and pricing"""
        count = count or settings.num_products
        products = []
        
        categories = {
            'Electronics': ['Smartphones', 'Laptops', 'Headphones', 'Tablets', 'Cameras'],
            'Clothing': ['Shirts', 'Pants', 'Dresses', 'Shoes', 'Accessories'],
            'Home': ['Furniture', 'Kitchen', 'Decor', 'Bedding', 'Storage'],
            'Books': ['Fiction', 'Non-fiction', 'Technical', 'Children', 'Comics'],
            'Sports': ['Equipment', 'Apparel', 'Footwear', 'Outdoor', 'Fitness']
        }
        
        brands = ['Apple', 'Samsung', 'Nike', 'Adidas', 'Sony', 'Dell', 'HP', 'Generic', 'Premium', 'Budget']
        
        for _ in range(count):
            category = random.choice(list(categories.keys()))
            subcategory = random.choice(categories[category])
            brand = random.choice(brands)
            
            # Price varies by category and brand
            base_price = random.uniform(10, 1000)
            if category == 'Electronics':
                base_price *= random.uniform(2, 5)
            if brand in ['Apple', 'Premium']:
                base_price *= random.uniform(1.5, 3)
            elif brand in ['Generic', 'Budget']:
                base_price *= random.uniform(0.3, 0.8)
                
            cost = base_price * random.uniform(0.3, 0.7)  # Realistic margins
            
            product = Product(
                product_id=str(uuid.uuid4()),
                name=f"{brand} {fake.catch_phrase()}",
                category=category,
                subcategory=subcategory,
                price=round(base_price, 2),
                cost=round(cost, 2),
                brand=brand,
                description=fake.text(max_nb_chars=200),
                is_active=random.random() < 0.9,  # 90% active products
                created_at=fake.date_time_between(start_date='-1y', end_date='now')
            )
            products.append(product)
            
        self.products = products
        return products
    
    def generate_transactions(self, days: int = None) -> List[Transaction]:
        """Generate realistic transactions with user behavior patterns"""
        days = days or settings.days_of_data
        transactions = []
        
        if not self.users or not self.products:
            raise ValueError("Must generate users and products first")
            
        active_users = [u for u in self.users if u.is_active]
        active_products = [p for p in self.products if p.is_active]
        
        # Generate transactions over time period
        start_date = datetime.now() - timedelta(days=days)
        
        for day in range(days):
            current_date = start_date + timedelta(days=day)
            
            # Weekend effect - more transactions on weekends
            weekend_multiplier = 1.3 if current_date.weekday() >= 5 else 1.0
            daily_transactions = int(len(active_users) * 0.05 * weekend_multiplier)
            
            for _ in range(daily_transactions):
                user = random.choice(active_users)
                product = random.choice(active_products)
                
                # Higher tier users buy more expensive items and more quantity
                tier_multiplier = 1 + 0.3 * list(UserTier).index(user.tier)
                quantity = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 15, 7, 3])[0]
                quantity = int(quantity * tier_multiplier)
                
                unit_price = product.price
                subtotal = unit_price * quantity
                
                # Discounts more common for higher tier users
                discount_prob = 0.1 + 0.05 * list(UserTier).index(user.tier)
                discount_amount = subtotal * random.uniform(0.05, 0.25) if random.random() < discount_prob else 0
                
                tax_amount = (subtotal - discount_amount) * 0.08  # 8% tax
                total_amount = subtotal - discount_amount + tax_amount
                
                # Transaction status - most succeed, some fail
                status_weights = [0.85, 0.10, 0.04, 0.01]  # completed, pending, failed, refunded
                status = random.choices(list(TransactionStatus), weights=status_weights)[0]
                
                transaction = Transaction(
                    transaction_id=str(uuid.uuid4()),
                    user_id=user.user_id,
                    product_id=product.product_id,
                    quantity=quantity,
                    unit_price=unit_price,
                    total_amount=round(total_amount, 2),
                    discount_amount=round(discount_amount, 2),
                    tax_amount=round(tax_amount, 2),
                    status=status,
                    payment_method=random.choice(['credit_card', 'debit_card', 'paypal', 'apple_pay']),
                    shipping_address=f"{fake.street_address()}, {fake.city()}, {fake.state()}",
                    created_at=current_date + timedelta(
                        hours=random.randint(0, 23),
                        minutes=random.randint(0, 59)
                    ),
                    updated_at=current_date + timedelta(
                        hours=random.randint(0, 23),
                        minutes=random.randint(0, 59)
                    )
                )
                transactions.append(transaction)
                
        return transactions
    
    def generate_user_events(self, days: int = None, events_per_day: int = None) -> List[UserEvent]:
        """Generate realistic user behavior events with session patterns"""
        days = days or settings.days_of_data
        events_per_day = events_per_day or settings.events_per_day
        events = []
        
        if not self.users or not self.products:
            raise ValueError("Must generate users and products first")
            
        active_users = [u for u in self.users if u.is_active]
        active_products = [p for p in self.products if p.is_active]
        
        start_date = datetime.now() - timedelta(days=days)
        
        for day in range(days):
            current_date = start_date + timedelta(days=day)
            
            # Generate sessions for random users
            daily_active_users = random.sample(
                active_users, 
                min(len(active_users), int(len(active_users) * random.uniform(0.1, 0.3)))
            )
            
            for user in daily_active_users:
                # Each user can have 1-3 sessions per day
                num_sessions = random.choices([1, 2, 3], weights=[60, 30, 10])[0]
                
                for session_num in range(num_sessions):
                    session_id = str(uuid.uuid4())
                    session_start = current_date + timedelta(
                        hours=random.randint(6, 23),
                        minutes=random.randint(0, 59)
                    )
                    
                    # Session duration: 2-30 minutes
                    session_duration = random.randint(2, 30)
                    
                    # Events per session: 3-20
                    events_in_session = random.randint(3, 20)
                    
                    # Generate realistic event sequence
                    event_sequence = self._generate_event_sequence(events_in_session)
                    
                    for i, event_type in enumerate(event_sequence):
                        event_time = session_start + timedelta(
                            minutes=random.randint(0, session_duration)
                        )
                        
                        # Event-specific properties
                        properties = {}
                        page_url = None
                        product_id = None
                        search_query = None
                        
                        if event_type == EventType.PAGE_VIEW:
                            page_url = f"/{random.choice(['home', 'products', 'about', 'contact'])}"
                        elif event_type in [EventType.PRODUCT_VIEW, EventType.ADD_TO_CART]:
                            product = random.choice(active_products)
                            product_id = product.product_id
                            page_url = f"/product/{product_id}"
                        elif event_type == EventType.SEARCH:
                            search_query = random.choice([
                                'laptop', 'phone', 'shoes', 'shirt', 'book', 'headphones'
                            ])
                            properties['results_count'] = random.randint(0, 100)
                        elif event_type == EventType.PURCHASE:
                            properties['amount'] = round(random.uniform(10, 500), 2)
                            
                        event = UserEvent(
                            event_id=str(uuid.uuid4()),
                            user_id=user.user_id,
                            session_id=session_id,
                            event_type=event_type,
                            timestamp=event_time,
                            page_url=page_url,
                            product_id=product_id,
                            search_query=search_query,
                            device_type=random.choice(['desktop', 'mobile', 'tablet']),
                            browser=random.choice(['chrome', 'firefox', 'safari', 'edge']),
                            ip_address=fake.ipv4(),
                            properties=properties
                        )
                        events.append(event)
                        
        return events
    
    def _generate_event_sequence(self, num_events: int) -> List[EventType]:
        """Generate realistic sequence of user events in a session"""
        sequence = []
        
        # Most sessions start with login or page_view
        sequence.append(random.choice([EventType.LOGIN, EventType.PAGE_VIEW]))
        
        for _ in range(num_events - 2):  # -2 for start and end events
            # Weighted probabilities for next event based on typical user flows
            if not sequence:
                next_event = EventType.PAGE_VIEW
            elif sequence[-1] == EventType.LOGIN:
                next_event = random.choice([EventType.PAGE_VIEW, EventType.SEARCH])
            elif sequence[-1] == EventType.SEARCH:
                next_event = random.choices(
                    [EventType.PRODUCT_VIEW, EventType.PAGE_VIEW, EventType.SEARCH],
                    weights=[50, 30, 20]
                )[0]
            elif sequence[-1] == EventType.PRODUCT_VIEW:
                next_event = random.choices(
                    [EventType.ADD_TO_CART, EventType.PRODUCT_VIEW, EventType.PAGE_VIEW],
                    weights=[30, 40, 30]
                )[0]
            elif sequence[-1] == EventType.ADD_TO_CART:
                next_event = random.choices(
                    [EventType.CHECKOUT_START, EventType.PRODUCT_VIEW, EventType.REMOVE_FROM_CART],
                    weights=[60, 30, 10]
                )[0]
            elif sequence[-1] == EventType.CHECKOUT_START:
                next_event = random.choices(
                    [EventType.PURCHASE, EventType.PAGE_VIEW],
                    weights=[70, 30]
                )[0]
            else:
                next_event = random.choice([EventType.PAGE_VIEW, EventType.PRODUCT_VIEW])
                
            sequence.append(next_event)
            
        # End with logout or just page activity
        sequence.append(random.choice([EventType.LOGOUT, EventType.PAGE_VIEW]))
        
        return sequence
    
    def export_to_csv(self, output_dir: str = "output"):
        """Export all generated data to CSV files"""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        if self.users:
            users_df = pd.DataFrame([user.model_dump() for user in self.users])
            users_df.to_csv(f"{output_dir}/users.csv", index=False)
            print(f"Exported {len(self.users)} users to {output_dir}/users.csv")
            
        if self.products:
            products_df = pd.DataFrame([product.model_dump() for product in self.products])
            products_df.to_csv(f"{output_dir}/products.csv", index=False)
            print(f"Exported {len(self.products)} products to {output_dir}/products.csv")
    
    def export_transactions_to_csv(self, transactions: List[Transaction], output_dir: str = "output"):
        """Export transactions to CSV"""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        transactions_df = pd.DataFrame([t.model_dump() for t in transactions])
        transactions_df.to_csv(f"{output_dir}/transactions.csv", index=False)
        print(f"Exported {len(transactions)} transactions to {output_dir}/transactions.csv")
    
    def export_events_to_csv(self, events: List[UserEvent], output_dir: str = "output"):
        """Export events to CSV"""
        import os
        os.makedirs(output_dir, exist_ok=True)
        
        events_df = pd.DataFrame([e.model_dump() for e in events])
        events_df.to_csv(f"{output_dir}/user_events.csv", index=False)
        print(f"Exported {len(events)} events to {output_dir}/user_events.csv")
    
    def stream_to_kafka(self, transactions: List[Transaction], events: List[UserEvent]):
        """Stream generated data to Kafka topics"""
        if not self.kafka_streamer:
            print("❌ Kafka streaming not enabled")
            return
        
        print("🚀 Streaming data to Kafka...")
        
        # Stream transactions
        if transactions:
            transaction_dicts = [t.model_dump() for t in transactions]
            success_count = self.kafka_streamer.stream_batch(
                topic=settings.kafka_topic_transactions,
                events=transaction_dicts,
                key_field='user_id'
            )
            print(f"✅ Streamed {success_count}/{len(transactions)} transactions to {settings.kafka_topic_transactions}")
        
        # Stream user events
        if events:
            event_dicts = [e.model_dump() for e in events]
            success_count = self.kafka_streamer.stream_batch(
                topic=settings.kafka_topic_events,
                events=event_dicts,
                key_field='user_id'
            )
            print(f"✅ Streamed {success_count}/{len(events)} events to {settings.kafka_topic_events}")
    
    def stream_realtime_events(self, duration_minutes: int = 60, events_per_minute: int = 10):
        """Generate and stream both events and transactions in real-time"""
        if not self.kafka_streamer:
            print("❌ Kafka streaming not enabled")
            return
        
        if not self.users or not self.products:
            print("❌ Must generate users and products first")
            return
        
        print(f"🔄 Starting real-time streaming for {duration_minutes} minutes...")
        print(f"📊 Target: {events_per_minute} events per minute + transactions")
        
        active_users = [u for u in self.users if u.is_active]
        active_products = [p for p in self.products if p.is_active]
        
        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)
        events_generated = 0
        transactions_generated = 0
        
        try:
            while time.time() < end_time:
                # Generate user events batch
                batch_events = []
                
                for _ in range(events_per_minute):
                    user = random.choice(active_users)
                    event_type = random.choice(list(EventType))
                    
                    # Create realistic event
                    properties = {}
                    page_url = None
                    product_id = None
                    search_query = None
                    
                    if event_type == EventType.PAGE_VIEW:
                        page_url = f"/{random.choice(['home', 'products', 'about', 'contact'])}"
                    elif event_type in [EventType.PRODUCT_VIEW, EventType.ADD_TO_CART]:
                        product = random.choice(active_products)
                        product_id = product.product_id
                        page_url = f"/product/{product_id}"
                    elif event_type == EventType.SEARCH:
                        search_query = random.choice([
                            'laptop', 'phone', 'shoes', 'shirt', 'book', 'headphones'
                        ])
                        properties['results_count'] = random.randint(0, 100)
                    elif event_type == EventType.PURCHASE:
                        properties['amount'] = round(random.uniform(10, 500), 2)
                    
                    event = UserEvent(
                        event_id=str(uuid.uuid4()),
                        user_id=user.user_id,
                        session_id=str(uuid.uuid4()),
                        event_type=event_type,
                        timestamp=datetime.now(),
                        page_url=page_url,
                        product_id=product_id,
                        search_query=search_query,
                        device_type=random.choice(['desktop', 'mobile', 'tablet']),
                        browser=random.choice(['chrome', 'firefox', 'safari', 'edge']),
                        ip_address=fake.ipv4(),
                        properties=properties
                    )
                    batch_events.append(event)
                
                # Generate transactions (realistic ratio: ~10% of events result in transactions)
                batch_transactions = []
                transactions_to_generate = max(1, events_per_minute // 10)  # At least 1 transaction per minute
                
                for _ in range(transactions_to_generate):
                    user = random.choice(active_users)
                    product = random.choice(active_products)
                    
                    # Higher tier users buy more expensive items and more quantity
                    tier_multiplier = 1 + 0.3 * list(UserTier).index(user.tier)
                    quantity = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 15, 7, 3])[0]
                    quantity = int(quantity * tier_multiplier)
                    
                    unit_price = product.price
                    subtotal = unit_price * quantity
                    
                    # Discounts more common for higher tier users
                    discount_prob = 0.1 + 0.05 * list(UserTier).index(user.tier)
                    discount_amount = subtotal * random.uniform(0.05, 0.25) if random.random() < discount_prob else 0
                    
                    tax_amount = (subtotal - discount_amount) * 0.08  # 8% tax
                    total_amount = subtotal - discount_amount + tax_amount
                    
                    # Transaction status - most succeed in real-time
                    status_weights = [0.90, 0.05, 0.03, 0.02]  # completed, pending, failed, refunded
                    status = random.choices(list(TransactionStatus), weights=status_weights)[0]
                    
                    transaction = Transaction(
                        transaction_id=str(uuid.uuid4()),
                        user_id=user.user_id,
                        product_id=product.product_id,
                        quantity=quantity,
                        unit_price=unit_price,
                        total_amount=round(total_amount, 2),
                        discount_amount=round(discount_amount, 2),
                        tax_amount=round(tax_amount, 2),
                        status=status,
                        payment_method=random.choice(['credit_card', 'debit_card', 'paypal', 'apple_pay']),
                        shipping_address=f"{fake.street_address()}, {fake.city()}, {fake.state()}",
                        created_at=datetime.now(),
                        updated_at=datetime.now()
                    )
                    batch_transactions.append(transaction)
                
                # Stream user events
                if batch_events:
                    event_dicts = [e.model_dump() for e in batch_events]
                    events_success = self.kafka_streamer.stream_batch(
                        topic=settings.kafka_topic_events,
                        events=event_dicts,
                        key_field='user_id'
                    )
                    events_generated += events_success
                
                # Stream transactions
                if batch_transactions:
                    transaction_dicts = [t.model_dump() for t in batch_transactions]
                    transactions_success = self.kafka_streamer.stream_batch(
                        topic=settings.kafka_topic_transactions,
                        events=transaction_dicts,
                        key_field='user_id'
                    )
                    transactions_generated += transactions_success
                
                # Progress update every minute
                elapsed_minutes = (time.time() - start_time) / 60
                if int(elapsed_minutes) % 1 == 0:  # Every minute
                    print(f"⏱️  {elapsed_minutes:.0f}m: Generated {events_generated} events, {transactions_generated} transactions")
                
                # Wait for next minute
                time.sleep(60)
                
        except KeyboardInterrupt:
            print("\n🛑 Streaming interrupted by user")
        
        elapsed_minutes = (time.time() - start_time) / 60
        print(f"✅ Real-time streaming completed. Generated {events_generated} events and {transactions_generated} transactions in {elapsed_minutes:.1f} minutes")
    
    def close(self):
        """Clean up resources"""
        if self.kafka_streamer:
            self.kafka_streamer.close()

def main():
    """CLI interface for data generation"""
    import click
    
    @click.command()
    @click.option('--users', default=1000, help='Number of users to generate')
    @click.option('--products', default=500, help='Number of products to generate')
    @click.option('--days', default=30, help='Days of transaction history')
    @click.option('--output', default='output', help='Output directory')
    @click.option('--stream', is_flag=True, help='Enable Kafka streaming')
    @click.option('--realtime', is_flag=True, help='Generate real-time streaming events')
    @click.option('--duration', default=60, help='Duration for real-time streaming (minutes)')
    @click.option('--rate', default=10, help='Events per minute for real-time streaming')
    def generate_data(users, products, days, output, stream, realtime, duration, rate):
        """Generate realistic e-commerce data"""
        
        # Initialize generator with streaming if requested
        generator = DataGenerator(enable_streaming=stream or realtime)
        
        try:
            if realtime:
                print("🔄 Real-time streaming mode")
                print("Generating base users and products...")
                generator.generate_users(users)
                generator.generate_products(products)
                
                # Start real-time streaming
                generator.stream_realtime_events(duration_minutes=duration, events_per_minute=rate)
                
            else:
                print(f"📊 Batch generation mode: {users} users, {products} products, {days} days of history")
                
                # Generate core data
                print("Generating users...")
                generator.generate_users(users)
                
                print("Generating products...")
                generator.generate_products(products)
                
                print("Generating transactions...")
                transactions = generator.generate_transactions(days)
                
                print("Generating user events...")
                events = generator.generate_user_events(days)
                
                # Stream to Kafka if enabled
                if stream:
                    generator.stream_to_kafka(transactions, events)
                
                # Always export to CSV for backup/analysis
                print(f"📁 Exporting to {output}/...")
                generator.export_to_csv(output)
                generator.export_transactions_to_csv(transactions, output)
                generator.export_events_to_csv(events, output)
                
                print("✅ Data generation complete!")
                print(f"Generated:")
                print(f"  - {len(generator.users)} users")
                print(f"  - {len(generator.products)} products") 
                print(f"  - {len(transactions)} transactions")
                print(f"  - {len(events)} user events")
                
                if stream:
                    print(f"🚀 Data streamed to Kafka topics:")
                    print(f"  - {settings.kafka_topic_transactions}")
                    print(f"  - {settings.kafka_topic_events}")
                    
        except KeyboardInterrupt:
            print("\n🛑 Generation interrupted by user")
        except Exception as e:
            print(f"❌ Error during generation: {e}")
        finally:
            # Clean up resources
            generator.close()
    
    generate_data()

if __name__ == "__main__":
    main()