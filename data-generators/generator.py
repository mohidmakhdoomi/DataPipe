import random
import uuid
import json
import time
import multiprocessing
from datetime import datetime, timedelta
from typing import List, Dict, Optional
from concurrent.futures import ThreadPoolExecutor
from queue import Empty
import pandas as pd
from faker import Faker
from kafka import KafkaProducer
from kafka.errors import KafkaError
from models import User, Product, Transaction, UserEvent, UserTier, TransactionStatus, EventType
from config import settings

# Try to import orjson for faster serialization, fallback to json
try:
    import orjson
    USE_ORJSON = True
except ImportError:
    import json as orjson
    USE_ORJSON = False

fake = Faker()

class HighPerformanceKafkaStreamer:
    """High-performance Kafka streamer optimized for 10K+ events/second"""
    
    def __init__(self):
        self.producer = None
        self._initialize_producer()
    
    def _initialize_producer(self):
        """Initialize high-throughput Kafka producer"""
        # Detect available compression libraries
        compression_type = None
        try:
            import snappy
            compression_type = 'snappy'
            print("✅ Snappy compression available")
        except ImportError:
            try:
                import lz4
                compression_type = 'lz4'
                print("✅ LZ4 compression available")
            except ImportError:
                try:
                    import zstandard
                    compression_type = 'zstd'
                    print("✅ Zstandard compression available")
                except ImportError:
                    compression_type = None
                    print("⚠️  No compression libraries available, using uncompressed")
        
        # Retry connection with backoff for resilience
        max_retries = 3
        for attempt in range(max_retries):
            try:
                # Serializer selection based on available libraries
                if USE_ORJSON:
                    value_serializer = lambda v: orjson.dumps(v)
                else:
                    value_serializer = lambda v: json.dumps(v, default=str).encode('utf-8')
                
                # Base configuration with improved resilience
                config = {
                    'bootstrap_servers': settings.kafka_bootstrap_servers,
                    'value_serializer': value_serializer,
                    'key_serializer': lambda k: str(k).encode('utf-8') if k else None,
                    
                    # High-throughput optimizations
                    'batch_size': 65536,              # 64KB batches
                    'linger_ms': 5,                   # Small batching delay for throughput
                    'acks': 1,                        # Leader-only acknowledgment (faster)
                    'buffer_memory': 134217728,       # 128MB buffer
                    'max_in_flight_requests_per_connection': 10,
                    'send_buffer_bytes': 262144,      # 256KB
                    'receive_buffer_bytes': 65536,    # 64KB
                    'retries': 5,                     # More retries for resilience
                    'retry_backoff_ms': 100,          # Fast retry backoff
                    'request_timeout_ms': 10000,      # Shorter timeout to fail fast
                    'max_block_ms': 2000,             # Longer block time for initial connection
                    'metadata_max_age_ms': 30000,     # Refresh metadata more frequently
                    'connections_max_idle_ms': 540000 # Keep connections alive longer
                }
                
                # Add compression if available
                if compression_type:
                    config['compression_type'] = compression_type
                
                self.producer = KafkaProducer(**config)
                
                print(f"✅ High-performance Kafka producer connected to {settings.kafka_bootstrap_servers}")
                if USE_ORJSON:
                    print("✅ Using orjson for faster serialization")
                if compression_type:
                    print(f"✅ Using {compression_type} compression")
                else:
                    print("⚠️  Running without compression (may impact performance)")
                
                return  # Success, exit retry loop
                
            except Exception as e:
                if attempt < max_retries - 1:
                    wait_time = (attempt + 1) * 2  # Exponential backoff: 2s, 4s, 6s
                    print(f"⚠️  Kafka connection attempt {attempt + 1} failed, retrying in {wait_time}s...")
                    time.sleep(wait_time)
                else:
                    print(f"❌ Failed to connect to Kafka after {max_retries} attempts: {e}")
        
        # If all retries failed, try fallback configuration
        try:
            print("🔄 Attempting fallback configuration...")
            fallback_config = {
                'bootstrap_servers': settings.kafka_bootstrap_servers,
                'value_serializer': lambda v: json.dumps(v, default=str).encode('utf-8'),
                'key_serializer': lambda k: str(k).encode('utf-8') if k else None,
                'acks': 1,
                'retries': 3,
                'batch_size': 16384,  # Smaller batch size
                'linger_ms': 10,
                'request_timeout_ms': 30000
            }
            self.producer = KafkaProducer(**fallback_config)
            print("✅ Fallback Kafka producer connected (basic configuration)")
        except Exception as fallback_error:
            print(f"❌ Fallback connection also failed: {fallback_error}")
            self.producer = None
    
    def stream_batch_async(self, topic: str, events: List[dict], key_field: str = None):
        """Stream batch of events asynchronously for maximum throughput"""
        if not self.producer:
            return 0
        
        successfully_queued = 0
        error_count = 0
        
        for event in events:
            key = event.get(key_field) if key_field else None
            try:
                # Send to Kafka - this queues the message in the producer buffer
                self.producer.send(topic=topic, value=event, key=key)
                successfully_queued += 1
            except Exception as e:
                error_count += 1
                # Only print errors occasionally to avoid spam
                if error_count <= 5 or error_count % 1000 == 0:
                    print(f"❌ Error queuing event ({error_count} total): {e}")
        
        # Return count of events successfully queued to Kafka producer
        # These will be sent asynchronously by the producer
        return successfully_queued
    
    def flush_async(self, timeout: float = 0.1):
        """Non-blocking flush with timeout"""
        if self.producer:
            try:
                self.producer.flush(timeout=timeout)
            except Exception:
                pass  # Ignore flush timeouts for performance
    
    def close(self):
        """Close producer"""
        if self.producer:
            self.producer.close()

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

class HighPerformanceEventPools:
    """Pre-computed pools for ultra-fast event generation"""
    
    def __init__(self, pool_sizes: Dict[str, int] = None):
        if pool_sizes is None:
            pool_sizes = {
                'uuids': 1000000,      # 1M UUIDs
                'sessions': 100000,     # 100K session IDs
                'ips': 10000,          # 10K IP addresses
                'user_agents': 1000,   # 1K user agent strings
                'urls': 5000           # 5K URLs
            }
        
        print("🔄 Pre-computing high-performance pools...")
        start_time = time.time()
        
        # Pre-generate expensive operations
        self.uuid_pool = [str(uuid.uuid4()) for _ in range(pool_sizes['uuids'])]
        self.session_pool = [str(uuid.uuid4()) for _ in range(pool_sizes['sessions'])]
        self.ip_pool = [fake.ipv4() for _ in range(pool_sizes['ips'])]
        
        # Pre-generate user agent strings
        browsers = ['Chrome', 'Firefox', 'Safari', 'Edge', 'Opera']
        versions = ['90.0', '91.0', '92.0', '93.0', '94.0', '95.0']
        self.user_agent_pool = [
            f"{random.choice(browsers)}/{random.choice(versions)}" 
            for _ in range(pool_sizes['user_agents'])
        ]
        
        # Pre-generate realistic URLs
        pages = ['home', 'products', 'about', 'contact', 'search', 'checkout', 'profile', 'cart']
        categories = ['electronics', 'clothing', 'books', 'sports', 'home']
        self.url_pool = [f"/{random.choice(pages)}" for _ in range(pool_sizes['urls'] // 2)]
        self.url_pool.extend([f"/category/{random.choice(categories)}" for _ in range(pool_sizes['urls'] // 4)])
        self.url_pool.extend([f"/product/{uuid.uuid4()}" for _ in range(pool_sizes['urls'] // 4)])
        
        # Fixed arrays for ultra-fast access
        self.device_types = ['desktop', 'mobile', 'tablet']
        self.browsers = ['chrome', 'firefox', 'safari', 'edge']
        self.event_types = list(EventType)
        
        # Event type weights for realistic distribution
        self.event_type_weights = [0.35, 0.25, 0.15, 0.10, 0.05, 0.04, 0.03, 0.02, 0.01]
        
        # Counters for round-robin access (reduces random calls)
        self.uuid_counter = 0
        self.session_counter = 0
        self.ip_counter = 0
        self.url_counter = 0
        
        elapsed = time.time() - start_time
        print(f"✅ Pre-computed pools ready in {elapsed:.2f}s")
        print(f"   - {len(self.uuid_pool):,} UUIDs")
        print(f"   - {len(self.session_pool):,} session IDs") 
        print(f"   - {len(self.ip_pool):,} IP addresses")
        print(f"   - {len(self.url_pool):,} URLs")
    
    def get_uuid(self) -> str:
        """Get UUID from pool using round-robin + random offset"""
        idx = (self.uuid_counter + random.randint(0, 1000)) % len(self.uuid_pool)
        self.uuid_counter = (self.uuid_counter + 1) % len(self.uuid_pool)
        return self.uuid_pool[idx]
    
    def get_session_id(self) -> str:
        """Get session ID from pool"""
        idx = (self.session_counter + random.randint(0, 100)) % len(self.session_pool)
        self.session_counter = (self.session_counter + 1) % len(self.session_pool)
        return self.session_pool[idx]
    
    def get_ip(self) -> str:
        """Get IP address from pool"""
        return self.ip_pool[random.randint(0, len(self.ip_pool) - 1)]
    
    def get_url(self) -> str:
        """Get URL from pool"""
        return self.url_pool[random.randint(0, len(self.url_pool) - 1)]
    
    def get_user_agent(self) -> str:
        """Get user agent from pool"""
        return self.user_agent_pool[random.randint(0, len(self.user_agent_pool) - 1)]

class DataGenerator:
    def __init__(self, enable_streaming: bool = False, high_performance: bool = False):
        self.users: List[User] = []
        self.products: List[Product] = []
        self.user_sessions: Dict[str, List[str]] = {}  # user_id -> session_ids
        
        # Choose streamer based on performance requirements
        if high_performance:
            self.kafka_streamer = HighPerformanceKafkaStreamer() if enable_streaming else None
            self.performance_pools = HighPerformanceEventPools()
        else:
            self.kafka_streamer = KafkaStreamer() if enable_streaming else None
            self.performance_pools = None
        
        # Cached selections for fast access
        self.active_users_cache = []
        self.active_products_cache = []
        self.weighted_users = []
        self.weighted_products = []
    
    def _create_weighted_selections(self):
        """Create weighted user and product selections for fast access"""
        if not self.users or not self.products:
            return
        
        print("🔄 Creating weighted selections for high-performance access...")
        
        # Cache active users and products
        self.active_users_cache = [u for u in self.users if u.is_active]
        self.active_products_cache = [p for p in self.products if p.is_active]
        
        # Create weighted selections based on user tiers (higher tiers more active)
        self.weighted_users = []
        for user in self.active_users_cache:
            tier_weight = 1 + list(UserTier).index(user.tier)  # Bronze=1, Silver=2, Gold=3, Platinum=4
            self.weighted_users.extend([user] * tier_weight)
        
        # Create weighted product selections (some products more popular)
        self.weighted_products = []
        for product in self.active_products_cache:
            # Simulate popularity - some products appear more frequently
            popularity_weight = random.choices([1, 2, 3, 4, 5], weights=[40, 30, 20, 7, 3])[0]
            self.weighted_products.extend([product] * popularity_weight)
        
        print(f"✅ Weighted selections ready:")
        print(f"   - {len(self.active_users_cache)} active users -> {len(self.weighted_users)} weighted")
        print(f"   - {len(self.active_products_cache)} active products -> {len(self.weighted_products)} weighted")
    
    def generate_event_batch_ultra_fast(self, batch_size: int, current_timestamp: float = None) -> List[dict]:
        """Ultra-fast event generation using pre-computed pools"""
        if not self.performance_pools or not self.weighted_users:
            raise ValueError("High-performance mode not initialized or no users available")
        
        if current_timestamp is None:
            current_timestamp = time.time()
        
        events = []
        pools = self.performance_pools
        
        # Generate events directly as dicts (skip object creation overhead)
        for i in range(batch_size):
            # Fast selections using weighted pools
            user = self.weighted_users[random.randint(0, len(self.weighted_users) - 1)]
            event_type = random.choices(pools.event_types, weights=pools.event_type_weights)[0]
            
            # Create event dict directly
            event = {
                'event_id': pools.get_uuid(),
                'user_id': user.user_id,
                'session_id': pools.get_session_id(),
                'event_type': event_type.value,
                'timestamp': current_timestamp + (i * 0.0001),  # Microsecond spacing
                'page_url': pools.get_url(),
                'product_id': None,
                'search_query': None,
                'device_type': pools.device_types[i % len(pools.device_types)],
                'browser': pools.browsers[i % len(pools.browsers)],
                'ip_address': pools.get_ip(),
                'properties': {},
                '_timestamp': datetime.fromtimestamp(current_timestamp + (i * 0.0001)).isoformat(),
                '_source': 'high-performance-generator'
            }
            
            # Add event-specific properties
            if event_type in [EventType.PRODUCT_VIEW, EventType.ADD_TO_CART]:
                if self.weighted_products:
                    product = self.weighted_products[random.randint(0, len(self.weighted_products) - 1)]
                    event['product_id'] = product.product_id
                    event['page_url'] = f"/product/{product.product_id}"
            elif event_type == EventType.SEARCH:
                search_terms = ['laptop', 'phone', 'shoes', 'shirt', 'book', 'headphones', 'watch', 'camera']
                event['search_query'] = search_terms[i % len(search_terms)]
                event['properties'] = {'results_count': random.randint(0, 100)}
            elif event_type == EventType.PURCHASE:
                event['properties'] = {'amount': round(random.uniform(10, 500), 2)}
            
            events.append(event)
        
        return events
    
    def generate_transaction_batch_fast(self, batch_size: int, current_timestamp: float = None) -> List[dict]:
        """Fast transaction generation"""
        if not self.weighted_users or not self.weighted_products:
            return []
        
        if current_timestamp is None:
            current_timestamp = time.time()
        
        transactions = []
        
        for i in range(batch_size):
            user = self.weighted_users[random.randint(0, len(self.weighted_users) - 1)]
            product = self.weighted_products[random.randint(0, len(self.weighted_products) - 1)]
            
            # Fast transaction calculation
            tier_multiplier = 1 + 0.3 * list(UserTier).index(user.tier)
            quantity = random.choices([1, 2, 3, 4, 5], weights=[50, 25, 15, 7, 3])[0]
            quantity = int(quantity * tier_multiplier)
            
            unit_price = product.price
            subtotal = unit_price * quantity
            discount_amount = subtotal * random.uniform(0.05, 0.25) if random.random() < 0.15 else 0
            tax_amount = (subtotal - discount_amount) * 0.08
            total_amount = subtotal - discount_amount + tax_amount
            
            transaction = {
                'transaction_id': self.performance_pools.get_uuid() if self.performance_pools else str(uuid.uuid4()),
                'user_id': user.user_id,
                'product_id': product.product_id,
                'quantity': quantity,
                'unit_price': unit_price,
                'total_amount': round(total_amount, 2),
                'discount_amount': round(discount_amount, 2),
                'tax_amount': round(tax_amount, 2),
                'status': 'completed',  # Simplified for performance
                'payment_method': ['credit_card', 'debit_card', 'paypal', 'apple_pay'][i % 4],
                'shipping_address': f"Address {i}",  # Simplified for performance
                'created_at': datetime.fromtimestamp(current_timestamp + (i * 0.0001)).isoformat(),
                'updated_at': datetime.fromtimestamp(current_timestamp + (i * 0.0001)).isoformat(),
                '_timestamp': datetime.fromtimestamp(current_timestamp + (i * 0.0001)).isoformat(),
                '_source': 'high-performance-generator'
            }
            transactions.append(transaction)
        
        return transactions
        
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
    
    def stream_realtime_events(self, duration_minutes: int = 60, events_per_second: int = 10):
        """Legacy single-threaded streaming (kept for compatibility)"""
        if events_per_second <= 100:
            return self._stream_realtime_events_legacy(duration_minutes, events_per_second)
        else:
            return self.stream_realtime_events_optimized(duration_minutes, events_per_second)
    
    def _stream_realtime_events_legacy(self, duration_minutes: int = 60, events_per_second: int = 10):
        """Original single-threaded implementation for low throughput"""
        if not self.kafka_streamer:
            print("❌ Kafka streaming not enabled")
            return
        
        if not self.users or not self.products:
            print("❌ Must generate users and products first")
            return
        
        print(f"🔄 Starting legacy real-time streaming for {duration_minutes} minutes...")
        print(f"📊 Target: {events_per_second} events per second + transactions")
        
        # Use cached selections if available
        if not self.active_users_cache:
            self._create_weighted_selections()
        
        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)
        events_generated = 0
        transactions_generated = 0
        
        try:
            while time.time() < end_time:
                batch_start = time.time()
                
                # Generate events using fast method if available
                if self.performance_pools and self.weighted_users:
                    batch_events = self.generate_event_batch_ultra_fast(events_per_second, batch_start)
                    events_success = self.kafka_streamer.stream_batch_async(
                        topic=settings.kafka_topic_events,
                        events=batch_events,
                        key_field='user_id'
                    )
                    events_generated += events_success
                    
                    # Generate transactions
                    transactions_to_generate = max(1, events_per_second // 10)
                    batch_transactions = self.generate_transaction_batch_fast(transactions_to_generate, batch_start)
                    if batch_transactions:
                        transactions_success = self.kafka_streamer.stream_batch_async(
                            topic=settings.kafka_topic_transactions,
                            events=batch_transactions,
                            key_field='user_id'
                        )
                        transactions_generated += transactions_success
                else:
                    # Fallback to original method
                    print("⚠️  Using original method - consider enabling high_performance mode")
                    break
                
                # Timing control
                elapsed = time.time() - batch_start
                sleep_time = 1.0 - elapsed
                if sleep_time > 0:
                    time.sleep(sleep_time)
                
                # Periodic flush
                if events_generated % (events_per_second * 5) == 0:  # Every 5 seconds
                    self.kafka_streamer.flush_async()
                
                if int(time.time() - start_time) % 10 == 0:  # Every 10 seconds
                    print(f"⏱️  {(time.time() - start_time)/60:.1f}m: Generated {events_generated} events, {transactions_generated} transactions")
                
        except KeyboardInterrupt:
            print("\n🛑 Streaming interrupted by user")
        
        elapsed_minutes = (time.time() - start_time) / 60
        print(f"✅ Real-time streaming completed. Generated {events_generated} events and {transactions_generated} transactions in {elapsed_minutes:.1f} minutes")
    
    def stream_realtime_events_optimized(self, duration_minutes: int = 60, events_per_second: int = 10000):
        """High-performance multiprocessing implementation for 1K+ events/second"""
        if not isinstance(self.kafka_streamer, HighPerformanceKafkaStreamer):
            print("❌ High-performance streaming requires HighPerformanceKafkaStreamer")
            print("💡 Initialize with DataGenerator(enable_streaming=True, high_performance=True)")
            return
        
        if not self.users or not self.products:
            print("❌ Must generate users and products first")
            return
        
        print(f"🚀 Starting HIGH-PERFORMANCE real-time streaming for {duration_minutes} minutes...")
        print(f"📊 Target: {events_per_second:,} events per second + {events_per_second//10:,} transactions per second")
        
        # Prepare weighted selections
        if not self.weighted_users:
            self._create_weighted_selections()
        
        # Optimized process distribution for high throughput
        cpu_count = multiprocessing.cpu_count()
        generator_processes = cpu_count // 4  # Use QUARTER cores for generation

        # Extreme process allocation for 10K+ events/second
        if events_per_second >= 10000:
            streamer_processes = 6  # One additional streamer for 10K+ throughput
        elif events_per_second >= 9000:
            streamer_processes = 5  # More streamers for high throughput
        elif events_per_second >= 7000:
            streamer_processes = 4
        elif events_per_second >= 5000:
            streamer_processes = 3
        else:
            streamer_processes = 2
        
        events_per_process = events_per_second // generator_processes
        
        print(f"🔧 Process configuration:")
        print(f"   - CPU cores available: {cpu_count}")
        print(f"   - Generator processes: {generator_processes}")
        print(f"   - Events per process: {events_per_process:,}/second")
        print(f"   - Streamer processes: {streamer_processes}")
        
        # Realistic queues with Kafka feedback tracking
        event_queue = multiprocessing.Queue(maxsize=10000)  # Realistic buffer size
        transaction_queue = multiprocessing.Queue(maxsize=1000)
        stats_queue = multiprocessing.Queue(maxsize=1000)
        
        # Shared counters for actual Kafka streaming success with locks
        manager = multiprocessing.Manager()
        kafka_events_streamed = manager.Value('i', 0)  # Actual events sent to Kafka
        kafka_transactions_streamed = manager.Value('i', 0)  # Actual transactions sent to Kafka
        kafka_events_lock = manager.Lock()  # Lock for thread-safe counter updates
        kafka_transactions_lock = manager.Lock()  # Lock for thread-safe counter updates
        
        # Shared stop event
        stop_event = multiprocessing.Event()
        
        try:
            # Start generator processes
            generators = []
            for i in range(generator_processes):
                p = multiprocessing.Process(
                    target=self._event_generator_worker,
                    args=(i, event_queue, transaction_queue, stats_queue, stop_event, 
                          events_per_process, duration_minutes)
                )
                generators.append(p)
                p.start()
                print(f"✅ Started generator process {i+1}/{generator_processes}")
            
            # Start streaming processes
            streamers = []
            for i in range(streamer_processes):
                p = multiprocessing.Process(
                    target=self._kafka_streaming_worker,
                    args=(i, event_queue, transaction_queue, stats_queue, stop_event, 
                          kafka_events_streamed, kafka_transactions_streamed,
                          kafka_events_lock, kafka_transactions_lock)
                )
                streamers.append(p)
                p.start()
                print(f"✅ Started streamer process {i+1}/{streamer_processes}")
            
            # Record start time for final calculations
            streaming_start_time = time.time()
            
            # Monitor performance with Kafka feedback
            self._monitor_high_performance_streaming(stats_queue, stop_event, duration_minutes, 
                                                    kafka_events_streamed, kafka_transactions_streamed)
            
        except KeyboardInterrupt:
            print("\n🛑 High-performance streaming interrupted by user")
        finally:
            # Clean shutdown
            print("🔄 Shutting down processes...")
            stop_event.set()
            
            # Wait for processes to finish
            for p in generators + streamers:
                p.join(timeout=5)
                if p.is_alive():
                    p.terminate()
            
            # Get final accurate counts after all processes have completed
            final_kafka_events = kafka_events_streamed.value
            final_kafka_transactions = kafka_transactions_streamed.value
            
            # Calculate final metrics
            total_elapsed_minutes = (time.time() - streaming_start_time) / 60
            final_kafka_rate = final_kafka_events / (total_elapsed_minutes * 60) if total_elapsed_minutes > 0 else 0
            
            print("✅ All processes shut down")
            
            # Print final accurate summary after all processes completed
            print(f"\n🎯 FINAL ACCURATE COUNTS (after all processes completed):")
            print(f"   - Total duration: {total_elapsed_minutes:.1f} minutes")
            print(f"   - Events queued to Kafka producer: {final_kafka_events:,} ({final_kafka_rate:.0f}/s)")
            print(f"   - Transactions queued to Kafka producer: {final_kafka_transactions:,}")
            print(f"💡 To verify actual Kafka topic data:")
            print(f"   docker exec docker-kafka-1 kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092")
    
    def _event_generator_worker(self, worker_id: int, event_queue, transaction_queue, stats_queue, 
                               stop_event, events_per_second: int, duration_minutes: int):
        """Optimized worker process for generating events at ultra-high speed"""
        try:
            # Initialize worker-specific data with optimized pools
            pool_sizes = {
                'uuids': 50000,       # Reduced for faster initialization
                'sessions': 5000,
                'ips': 500,
                'user_agents': 50,
                'urls': 200
            }
            worker_pools = HighPerformanceEventPools(pool_sizes)
            
            # Create local copies of weighted selections
            local_weighted_users = self.weighted_users.copy()
            local_weighted_products = self.weighted_products.copy()
            
            print(f"🔧 Generator worker {worker_id} initialized with {len(local_weighted_users)} users")
            
            # Ultra-aggressive batch sizing for 10K+ events/second
            if events_per_second >= 9000:
                batch_size = 10000  # Massive batches for ultra-high throughput
                batches_per_second = max(1, events_per_second // batch_size)
            elif events_per_second >= 5000:
                batch_size = 5000
                batches_per_second = max(1, events_per_second // batch_size)
            elif events_per_second >= 2000:
                batch_size = 2000
                batches_per_second = max(1, events_per_second // batch_size)
            else:
                batch_size = 1000
                batches_per_second = max(1, events_per_second // batch_size)
            
            # Eliminate timing constraints for maximum throughput
            target_interval = 0.001  # Minimal interval - generate as fast as possible
            
            start_time = time.time()
            end_time = start_time + (duration_minutes * 60)
            events_generated = 0
            transactions_generated = 0
            last_stats_time = start_time
            batch_count = 0
            
            # Pre-calculate transaction batch size
            transaction_batch_size = max(1, batch_size // 10)
            
            # Ultra-high speed generation loop - no timing constraints
            while time.time() < end_time and not stop_event.is_set():
                # Generate multiple batches in rapid succession
                for _ in range(5):  # Generate 5 batches per cycle for maximum throughput
                    if time.time() >= end_time or stop_event.is_set():
                        break
                    
                    cycle_start = time.time()
                    
                    # Generate event batch (ultra-optimized)
                    events = self._generate_ultra_fast_event_batch(
                        batch_size, worker_pools, local_weighted_users, local_weighted_products, cycle_start
                    )
                    
                    # Generate transaction batch (ultra-optimized)
                    transactions = self._generate_ultra_fast_transaction_batch(
                        transaction_batch_size, worker_pools, local_weighted_users, local_weighted_products, cycle_start
                    )
                    
                    # Queue operations - only count successfully queued events
                    try:
                        event_queue.put(events, block=False)
                        events_generated += len(events)  # Only count if successfully queued
                    except:
                        pass  # Don't count failed queue operations
                    
                    try:
                        transaction_queue.put(transactions, block=False)
                        transactions_generated += len(transactions)  # Only count if successfully queued
                    except:
                        pass  # Don't count failed queue operations
                    
                    batch_count += 1
                
                # Minimal stats reporting (every 20 seconds)
                current_time = time.time()
                if current_time - last_stats_time >= 20.0:
                    try:
                        stats_queue.put({
                            'worker_id': worker_id,
                            'events': events_generated,
                            'transactions': transactions_generated,
                            'timestamp': current_time,
                            'batches': batch_count
                        }, block=False)
                        last_stats_time = current_time
                    except:
                        pass
                
                # Tiny pause to prevent 100% CPU usage
                time.sleep(0.0001)  # 0.1ms pause
            
            # Reduce print overhead for performance
            if worker_id == 0:  # Only first worker prints to reduce output
                print(f"✅ Generator worker {worker_id} completed: {events_generated:,} events, {transactions_generated:,} transactions in {batch_count} batches")
            
        except Exception as e:
            print(f"❌ Generator worker {worker_id} error: {e}")
            import traceback
            traceback.print_exc()
    
    def _kafka_streaming_worker(self, worker_id: int, event_queue, transaction_queue, stats_queue, stop_event, 
                               kafka_events_streamed, kafka_transactions_streamed, kafka_events_lock, kafka_transactions_lock):
        """Optimized worker process for streaming to Kafka with accurate counting"""
        try:
            # Brief startup delay to let Kafka stabilize
            time.sleep(worker_id * 0.5 + 1)  # Staggered startup: 1s, 1.5s, 2s, 2.5s
            
            # Initialize high-performance Kafka producer
            streamer = HighPerformanceKafkaStreamer()
            
            print(f"🔧 Streamer worker {worker_id} initialized")
            
            events_streamed = 0
            transactions_streamed = 0
            flush_counter = 0
            last_flush_time = time.time()
            
            while not stop_event.is_set():
                batches_processed = 0
                cycle_start = time.time()
                
                # Process massive number of batches per cycle for 10K+ events/second
                while batches_processed < 200 and not stop_event.is_set():
                    events_processed = False
                    transactions_processed = False
                    
                    # Stream events with accurate Kafka feedback
                    try:
                        events = event_queue.get(block=False)
                        events_processed = True
                        batches_processed += 1
                        
                        if streamer.producer:  # Only stream if producer is available
                            try:
                                success_count = streamer.stream_batch_async(
                                    topic=settings.kafka_topic_events,
                                    events=events,
                                    key_field='user_id'
                                )
                                events_streamed += success_count
                                # Update shared counter with proper locking for thread safety
                                with kafka_events_lock:
                                    kafka_events_streamed.value += success_count
                            except Exception as e:
                                print(f"⚠️  Worker {worker_id}: Error streaming events batch: {e}")
                    except Empty:
                        pass  # No events available, continue
                    
                    # Stream transactions with accurate Kafka feedback
                    try:
                        transactions = transaction_queue.get(block=False)
                        transactions_processed = True
                        batches_processed += 1
                        
                        if streamer.producer:  # Only stream if producer is available
                            try:
                                success_count = streamer.stream_batch_async(
                                    topic=settings.kafka_topic_transactions,
                                    events=transactions,
                                    key_field='user_id'
                                )
                                transactions_streamed += success_count
                                # Update shared counter with proper locking for thread safety
                                with kafka_transactions_lock:
                                    kafka_transactions_streamed.value += success_count
                            except Exception as e:
                                print(f"⚠️  Worker {worker_id}: Error streaming transactions batch: {e}")
                    except Empty:
                        pass  # No transactions available, continue
                    
                    # Break if no data available
                    if not events_processed and not transactions_processed:
                        break
                
                # Extreme flushing optimization for 10K+ events/second
                flush_counter += batches_processed
                current_time = time.time()
                
                # Flush conditions optimized for extreme throughput
                should_flush = (
                    flush_counter >= 500 or  # Much higher volume threshold
                    (current_time - last_flush_time) >= 5.0 or  # Much less frequent time-based flushing
                    stop_event.is_set()  # Shutdown flush
                )
                
                if should_flush and flush_counter > 0:
                    try:
                        streamer.flush_async(timeout=0.01)  # Very short timeout
                        flush_counter = 0
                        last_flush_time = current_time
                    except:
                        pass  # Continue on flush errors
                
                # No pause - maximum throughput mode
                if batches_processed == 0:
                    pass  # No sleep - run at maximum speed
            
            # Final flush with longer timeout
            print(f"🔄 Streamer worker {worker_id} performing final flush...")
            try:
                streamer.flush_async(timeout=5.0)
            except:
                pass
            
            streamer.close()
            
            # Reduce print overhead for performance
            if worker_id == 0:  # Only first worker prints to reduce output
                print(f"✅ Streamer worker {worker_id} completed: {events_streamed:,} events, {transactions_streamed:,} transactions actually streamed to Kafka")
            
        except Exception as e:
            print(f"❌ Streamer worker {worker_id} error: {e}")
            import traceback
            traceback.print_exc()
    
    def _generate_ultra_fast_event_batch(self, batch_size: int, pools, users, products, timestamp: float) -> List[dict]:
        """Ultra-optimized event batch generation for maximum throughput"""
        events = []
        
        # Pre-calculate common values to reduce function calls
        user_count = len(users)
        product_count = len(products) if products else 0
        device_count = len(pools.device_types)
        browser_count = len(pools.browsers)
        event_type_count = len(pools.event_types)
        
        # Use deterministic cycling for maximum performance (no random calls)
        user_indices = [(i * 13) % user_count for i in range(batch_size)]
        event_type_indices = [(i * 17) % event_type_count for i in range(batch_size)]
        
        # Batch timestamp calculation
        base_timestamp = timestamp
        
        for i in range(batch_size):
            user = users[user_indices[i]]
            event_type = pools.event_types[event_type_indices[i]]
            
            # Ultra-fast event creation with minimal function calls and pre-computed values
            event_timestamp = base_timestamp + (i * 0.0001)
            event = {
                'event_id': pools.get_uuid(),
                'user_id': user.user_id,
                'session_id': pools.get_session_id(),
                'event_type': event_type.value,
                'timestamp': event_timestamp,
                'page_url': pools.get_url(),
                'product_id': None,
                'search_query': None,
                'device_type': pools.device_types[i % device_count],
                'browser': pools.browsers[i % browser_count],
                'ip_address': pools.get_ip(),
                'properties': {},
                '_timestamp': datetime.fromtimestamp(event_timestamp).isoformat(),
                '_source': 'ultra-high-performance-generator'
            }
            
            # Ultra-optimized event-specific properties (minimal branching)
            event_val = event_type.value
            if event_val in ['product_view', 'add_to_cart'] and product_count > 0:
                product = products[i % product_count]  # Cycle through products
                event['product_id'] = product.product_id
                event['page_url'] = f"/product/{product.product_id}"
            elif event_val == 'search':
                search_terms = ['laptop', 'phone', 'shoes', 'shirt', 'book', 'headphones']
                event['search_query'] = search_terms[i % 6]
                event['properties'] = {'results_count': 50 + (i % 50)}
            elif event_val == 'purchase':
                event['properties'] = {'amount': round(10 + (i % 490) + (i * 0.1), 2)}
            
            events.append(event)
        
        return events
    
    def _generate_fast_event_batch(self, batch_size: int, pools, users, products, timestamp: float) -> List[dict]:
        """Generate event batch optimized for speed (legacy method)"""
        return self._generate_ultra_fast_event_batch(batch_size, pools, users, products, timestamp)
    
    def _generate_ultra_fast_transaction_batch(self, batch_size: int, pools, users, products, timestamp: float) -> List[dict]:
        """Ultra-optimized transaction batch generation for maximum throughput"""
        if not products:
            return []
        
        transactions = []
        
        # Pre-calculate common values
        user_count = len(users)
        product_count = len(products)
        payment_methods = ['credit_card', 'debit_card', 'paypal']
        
        # Use cycling instead of random for maximum performance
        user_indices = [(i * 7) % user_count for i in range(batch_size)]  # Pseudo-random cycling
        product_indices = [(i * 11) % product_count for i in range(batch_size)]
        
        base_timestamp = timestamp
        
        for i in range(batch_size):
            user = users[user_indices[i]]
            product = products[product_indices[i]]
            
            # Ultra-fast calculation with minimal randomness
            quantity = 1 + (i % 3)  # Pseudo-random quantity (1, 2, or 3)
            unit_price = product.price
            subtotal = unit_price * quantity
            tax_amount = subtotal * 0.08
            total_amount = subtotal + tax_amount
            
            transaction = {
                'transaction_id': pools.get_uuid(),
                'user_id': user.user_id,
                'product_id': product.product_id,
                'quantity': quantity,
                'unit_price': unit_price,
                'total_amount': round(total_amount, 2),
                'discount_amount': 0.0,
                'tax_amount': round(tax_amount, 2),
                'status': 'completed',
                'payment_method': payment_methods[i % 3],
                'shipping_address': f"Address {i % 1000}",  # Cycle addresses
                'created_at': datetime.fromtimestamp(base_timestamp + (i * 0.0001)).isoformat(),
                'updated_at': datetime.fromtimestamp(base_timestamp + (i * 0.0001)).isoformat(),
                '_timestamp': datetime.fromtimestamp(base_timestamp + (i * 0.0001)).isoformat(),
                '_source': 'ultra-high-performance-generator'
            }
            transactions.append(transaction)
        
        return transactions
    
    def _generate_fast_transaction_batch(self, batch_size: int, pools, users, products, timestamp: float) -> List[dict]:
        """Generate transaction batch optimized for speed (legacy method)"""
        return self._generate_ultra_fast_transaction_batch(batch_size, pools, users, products, timestamp)
    
    def _monitor_high_performance_streaming(self, stats_queue, stop_event, duration_minutes: int,
                                          kafka_events_streamed, kafka_transactions_streamed):
        """Monitor high-performance streaming progress with accurate Kafka feedback"""
        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)
        
        total_events_queued = 0
        total_transactions_queued = 0
        worker_stats = {}
        
        print(f"📊 Monitoring high-performance streaming...")
        
        try:
            while time.time() < end_time and not stop_event.is_set():
                try:
                    # Collect stats from workers
                    while True:
                        try:
                            stats = stats_queue.get(timeout=1.0)
                            worker_id = stats['worker_id']
                            worker_stats[worker_id] = stats
                        except Empty:
                            break
                    
                    # Calculate totals from generator workers (events queued for streaming)
                    current_events_queued = sum(s.get('events', 0) for s in worker_stats.values())
                    current_transactions_queued = sum(s.get('transactions', 0) for s in worker_stats.values())
                    
                    # Get actual Kafka streaming counts (events successfully sent to Kafka)
                    kafka_events = kafka_events_streamed.value
                    kafka_transactions = kafka_transactions_streamed.value
                    
                    elapsed_minutes = (time.time() - start_time) / 60
                    queue_rate = current_events_queued / (elapsed_minutes * 60) if elapsed_minutes > 0 else 0
                    kafka_rate = kafka_events / (elapsed_minutes * 60) if elapsed_minutes > 0 else 0
                    
                    print(f"⚡ {elapsed_minutes:.1f}m: {current_events_queued:,} queued ({queue_rate:.0f}/s) | {kafka_events:,} sent to Kafka ({kafka_rate:.0f}/s)")
                    
                    total_events_queued = current_events_queued
                    total_transactions_queued = current_transactions_queued
                    
                    time.sleep(5)  # Report every 5 seconds
                    
                except KeyboardInterrupt:
                    break
        
        except KeyboardInterrupt:
            print("\n🛑 Monitoring interrupted")
        
        stop_event.set()
        elapsed_minutes = (time.time() - start_time) / 60
        avg_queue_rate = total_events_queued / (elapsed_minutes * 60) if elapsed_minutes > 0 else 0
        
        # Get final counts (managed objects are already thread-safe)
        final_kafka_events = kafka_events_streamed.value
        final_kafka_transactions = kafka_transactions_streamed.value
        
        avg_kafka_rate = final_kafka_events / (elapsed_minutes * 60) if elapsed_minutes > 0 else 0
        streaming_efficiency = (final_kafka_events / total_events_queued * 100) if total_events_queued > 0 else 0
        
        print(f"\n✅ HIGH-PERFORMANCE streaming completed:")
        print(f"   - Duration: {elapsed_minutes:.1f} minutes")
        print(f"   - Events queued by generators: {total_events_queued:,} ({avg_queue_rate:.0f}/s)")
        print(f"   - Events queued to Kafka producer: {final_kafka_events:,} ({avg_kafka_rate:.0f}/s)")
        print(f"   - Transactions queued to Kafka producer: {final_kafka_transactions:,}")
        print(f"   - Producer queue efficiency: {streaming_efficiency:.1f}%")
        
        # Add verification note with more context
        print(f"💡 To verify actual Kafka topic data:")
        print(f"   docker exec docker-kafka-1 kafka-run-class kafka.tools.GetOffsetShell --broker-list localhost:9092")
        print(f"📝 Note: Kafka producer queues events asynchronously, so actual topic counts may vary slightly")
    
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
    @click.option('--rate', default=10, help='Events per second for real-time streaming')
    @click.option('--high-performance', is_flag=True, help='Enable high-performance mode for 1K+ events/second')
    def generate_data(users, products, days, output, stream, realtime, duration, rate, high_performance):
        """Generate realistic e-commerce data"""
        
        # Validate high-performance requirements
        if high_performance and rate < 100:
            print("⚠️  High-performance mode recommended for 100+ events/second")
            print("💡 Consider using --rate 1000 or higher for best results")
        
        if rate >= 10000 and not high_performance:
            print("❌ High-performance mode required for 10K+ events/second")
            print("💡 Add --high-performance flag")
            return
        
        # Initialize generator with appropriate mode
        generator = DataGenerator(
            enable_streaming=stream or realtime, 
            high_performance=high_performance or rate >= 100
        )
        
        try:
            if realtime:
                mode_name = "HIGH-PERFORMANCE" if high_performance else "Standard"
                print(f"🔄 {mode_name} real-time streaming mode")
                print("Generating base users and products...")
                
                generator.generate_users(users)
                generator.generate_products(products)
                
                # Create weighted selections for performance
                generator._create_weighted_selections()
                
                if high_performance:
                    print(f"🚀 Starting high-performance streaming: {rate:,} events/second")
                    if rate >= 10000:
                        print("⚡ ULTRA-HIGH throughput mode activated!")
                
                # Start real-time streaming
                generator.stream_realtime_events(duration_minutes=duration, events_per_second=rate)
                
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