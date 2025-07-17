import random
import uuid
from datetime import datetime, timedelta
from typing import List, Dict
import pandas as pd
from faker import Faker
from models import User, Product, Transaction, UserEvent, UserTier, TransactionStatus, EventType
from config import settings

fake = Faker()

class DataGenerator:
    def __init__(self):
        self.users: List[User] = []
        self.products: List[Product] = []
        self.user_sessions: Dict[str, List[str]] = {}  # user_id -> session_ids
        
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

def main():
    """CLI interface for data generation"""
    import click
    
    @click.command()
    @click.option('--users', default=1000, help='Number of users to generate')
    @click.option('--products', default=500, help='Number of products to generate')
    @click.option('--days', default=30, help='Days of transaction history')
    @click.option('--output', default='output', help='Output directory')
    def generate_data(users, products, days, output):
        """Generate realistic e-commerce data"""
        print(f"Generating data: {users} users, {products} products, {days} days of history")
        
        generator = DataGenerator()
        
        # Generate core data
        print("Generating users...")
        generator.generate_users(users)
        
        print("Generating products...")
        generator.generate_products(products)
        
        print("Generating transactions...")
        transactions = generator.generate_transactions(days)
        
        print("Generating user events...")
        events = generator.generate_user_events(days)
        
        # Export to CSV
        print(f"Exporting to {output}/...")
        generator.export_to_csv(output)
        generator.export_transactions_to_csv(transactions, output)
        generator.export_events_to_csv(events, output)
        
        print("Data generation complete!")
        print(f"Generated:")
        print(f"  - {len(generator.users)} users")
        print(f"  - {len(generator.products)} products") 
        print(f"  - {len(transactions)} transactions")
        print(f"  - {len(events)} user events")
    
    generate_data()

if __name__ == "__main__":
    main()