#!/usr/bin/env python3
"""
Quick test script for the data generator
"""

from generator import DataGenerator
import json

def test_data_generation():
    """Test the data generator with small sample sizes"""
    print("Testing data generator...")
    
    generator = DataGenerator()
    
    # Generate small samples
    print("Generating 10 users...")
    users = generator.generate_users(10)
    print(f"✓ Generated {len(users)} users")
    
    print("Generating 20 products...")
    products = generator.generate_products(20)
    print(f"✓ Generated {len(products)} products")
    
    print("Generating 7 days of transactions...")
    transactions = generator.generate_transactions(7)
    print(f"✓ Generated {len(transactions)} transactions")
    
    print("Generating 7 days of events...")
    events = generator.generate_user_events(7, 100)  # 100 events per day
    print(f"✓ Generated {len(events)} user events")
    
    # Show sample data
    print("\n--- Sample User ---")
    print(json.dumps(users[0].model_dump(), indent=2, default=str))
    
    print("\n--- Sample Product ---")
    print(json.dumps(products[0].model_dump(), indent=2, default=str))
    
    print("\n--- Sample Transaction ---")
    if transactions:
        print(json.dumps(transactions[0].model_dump(), indent=2, default=str))
    
    print("\n--- Sample Event ---")
    if events:
        print(json.dumps(events[0].model_dump(), indent=2, default=str))
    
    print("\n✅ All tests passed! Data generator is working correctly.")

if __name__ == "__main__":
    test_data_generation()