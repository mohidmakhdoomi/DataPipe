#!/usr/bin/env python3
"""
Quick analysis script for generated data
"""

import pandas as pd
import os

def analyze_generated_data(data_dir="sample_data"):
    """Analyze the generated sample data"""
    if not os.path.exists(data_dir):
        print(f"Data directory {data_dir} not found. Run generator first.")
        return
    
    print(f"📊 Data Analysis for {data_dir}/")
    print("=" * 50)
    
    # Users analysis
    if os.path.exists(f"{data_dir}/users.csv"):
        users_df = pd.read_csv(f"{data_dir}/users.csv")
        print(f"\n👥 Users: {len(users_df)} total")
        print(f"   Active users: {users_df['is_active'].sum()}")
        print(f"   Tier distribution:")
        print(users_df['tier'].value_counts().to_string())
        
    # Products analysis
    if os.path.exists(f"{data_dir}/products.csv"):
        products_df = pd.read_csv(f"{data_dir}/products.csv")
        print(f"\n📦 Products: {len(products_df)} total")
        print(f"   Active products: {products_df['is_active'].sum()}")
        print(f"   Category distribution:")
        print(products_df['category'].value_counts().to_string())
        print(f"   Price range: ${products_df['price'].min():.2f} - ${products_df['price'].max():.2f}")
        
    # Transactions analysis
    if os.path.exists(f"{data_dir}/transactions.csv"):
        transactions_df = pd.read_csv(f"{data_dir}/transactions.csv")
        print(f"\n💳 Transactions: {len(transactions_df)} total")
        print(f"   Status distribution:")
        print(transactions_df['status'].value_counts().to_string())
        print(f"   Total revenue: ${transactions_df['total_amount'].sum():.2f}")
        print(f"   Average order value: ${transactions_df['total_amount'].mean():.2f}")
        print(f"   Payment methods:")
        print(transactions_df['payment_method'].value_counts().to_string())
        
    # Events analysis
    if os.path.exists(f"{data_dir}/user_events.csv"):
        events_df = pd.read_csv(f"{data_dir}/user_events.csv")
        print(f"\n📱 User Events: {len(events_df)} total")
        print(f"   Event type distribution:")
        print(events_df['event_type'].value_counts().to_string())
        print(f"   Device types:")
        print(events_df['device_type'].value_counts().to_string())
        print(f"   Unique sessions: {events_df['session_id'].nunique()}")
        
    print("\n✅ Data analysis complete!")

if __name__ == "__main__":
    analyze_generated_data()