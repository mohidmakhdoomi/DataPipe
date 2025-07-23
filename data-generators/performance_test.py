#!/usr/bin/env python3
"""
Performance testing script for the optimized data generator.
Tests various throughput levels and measures actual performance.
"""

import time
import sys
import os
from typing import Dict, List
import multiprocessing

# Add the current directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from generator import DataGenerator, HighPerformanceEventPools

def test_pool_creation_performance():
    """Test the performance of creating pre-computed pools"""
    print("🧪 Testing pool creation performance...")
    
    start_time = time.time()
    pools = HighPerformanceEventPools()
    creation_time = time.time() - start_time
    
    print(f"✅ Pool creation completed in {creation_time:.2f} seconds")
    print(f"   - UUID pool: {len(pools.uuid_pool):,} items")
    print(f"   - IP pool: {len(pools.ip_pool):,} items")
    print(f"   - Session pool: {len(pools.session_pool):,} items")
    
    return pools

def test_event_generation_speed(generator: DataGenerator, batch_sizes: List[int]):
    """Test event generation speed at different batch sizes"""
    print("\n🧪 Testing event generation speed...")
    
    if not generator.weighted_users:
        print("Creating weighted selections...")
        generator._create_weighted_selections()
    
    results = {}
    
    for batch_size in batch_sizes:
        print(f"\n📊 Testing batch size: {batch_size:,}")
        
        # Warm up
        generator.generate_event_batch_ultra_fast(100)
        
        # Measure performance
        iterations = max(1, 1000 // batch_size)  # Adjust iterations based on batch size
        start_time = time.time()
        
        total_events = 0
        for _ in range(iterations):
            events = generator.generate_event_batch_ultra_fast(batch_size)
            total_events += len(events)
        
        elapsed_time = time.time() - start_time
        events_per_second = total_events / elapsed_time
        
        results[batch_size] = {
            'events_per_second': events_per_second,
            'total_events': total_events,
            'elapsed_time': elapsed_time,
            'iterations': iterations
        }
        
        print(f"   - Generated {total_events:,} events in {elapsed_time:.3f}s")
        print(f"   - Performance: {events_per_second:.0f} events/second")
        print(f"   - Time per event: {(elapsed_time * 1000000) / total_events:.1f} μs")
    
    return results

def test_kafka_streaming_simulation(generator: DataGenerator, events_per_second: int, duration_seconds: int = 10):
    """Simulate Kafka streaming without actual Kafka connection"""
    print(f"\n🧪 Testing streaming simulation: {events_per_second:,} events/second for {duration_seconds}s")
    
    if not generator.weighted_users:
        generator._create_weighted_selections()
    
    batch_size = min(1000, events_per_second)
    batches_per_second = max(1, events_per_second // batch_size)
    sleep_time = 1.0 / batches_per_second
    
    start_time = time.time()
    end_time = start_time + duration_seconds
    total_events = 0
    total_batches = 0
    
    print(f"   - Batch size: {batch_size}")
    print(f"   - Batches per second: {batches_per_second}")
    print(f"   - Sleep time: {sleep_time:.4f}s")
    
    try:
        while time.time() < end_time:
            batch_start = time.time()
            
            # Generate batch
            events = generator.generate_event_batch_ultra_fast(batch_size, batch_start)
            total_events += len(events)
            total_batches += 1
            
            # Simulate serialization (major bottleneck in real streaming)
            serialized_events = []
            for event in events:
                # Simulate JSON serialization time
                serialized = str(event)  # Simple serialization simulation
                serialized_events.append(serialized)
            
            # Timing control
            elapsed = time.time() - batch_start
            if elapsed < sleep_time:
                time.sleep(sleep_time - elapsed)
            
            # Progress update
            if total_batches % (batches_per_second * 2) == 0:  # Every 2 seconds
                current_rate = total_events / (time.time() - start_time)
                print(f"   - Progress: {total_events:,} events ({current_rate:.0f}/s)")
    
    except KeyboardInterrupt:
        print("   - Test interrupted")
    
    elapsed_time = time.time() - start_time
    actual_rate = total_events / elapsed_time
    
    print(f"✅ Streaming simulation completed:")
    print(f"   - Duration: {elapsed_time:.2f}s")
    print(f"   - Total events: {total_events:,}")
    print(f"   - Total batches: {total_batches:,}")
    print(f"   - Target rate: {events_per_second:,}/s")
    print(f"   - Actual rate: {actual_rate:.0f}/s")
    print(f"   - Efficiency: {(actual_rate / events_per_second * 100):.1f}%")
    
    return {
        'target_rate': events_per_second,
        'actual_rate': actual_rate,
        'efficiency': actual_rate / events_per_second,
        'total_events': total_events,
        'elapsed_time': elapsed_time
    }

def run_comprehensive_performance_test():
    """Run comprehensive performance tests"""
    print("🚀 Starting comprehensive performance tests...")
    print(f"💻 System info: {multiprocessing.cpu_count()} CPU cores")
    
    # Test 1: Pool creation
    pools = test_pool_creation_performance()
    
    # Test 2: Initialize generator
    print("\n🔧 Initializing high-performance generator...")
    generator = DataGenerator(enable_streaming=False, high_performance=True)
    
    # Generate test data
    print("📊 Generating test users and products...")
    generator.generate_users(1000)
    generator.generate_products(500)
    generator._create_weighted_selections()
    
    print(f"✅ Test data ready: {len(generator.users)} users, {len(generator.products)} products")
    
    # Test 3: Event generation speed
    batch_sizes = [10, 100, 1000, 5000]
    generation_results = test_event_generation_speed(generator, batch_sizes)
    
    # Test 4: Streaming simulation at different rates
    streaming_rates = [100, 1000, 5000, 10000]
    streaming_results = {}
    
    for rate in streaming_rates:
        if rate <= 1000 or input(f"\n❓ Test {rate:,} events/second? (y/N): ").lower() == 'y':
            result = test_kafka_streaming_simulation(generator, rate, duration_seconds=5)
            streaming_results[rate] = result
        else:
            print(f"⏭️  Skipping {rate:,} events/second test")
    
    # Summary
    print("\n" + "="*60)
    print("📋 PERFORMANCE TEST SUMMARY")
    print("="*60)
    
    print("\n🏗️  Event Generation Performance:")
    for batch_size, result in generation_results.items():
        print(f"   - Batch {batch_size:,}: {result['events_per_second']:,.0f} events/second")
    
    print("\n🚀 Streaming Simulation Performance:")
    for rate, result in streaming_results.items():
        efficiency = result['efficiency'] * 100
        status = "✅" if efficiency >= 90 else "⚠️" if efficiency >= 70 else "❌"
        print(f"   - {rate:,}/s target: {result['actual_rate']:,.0f}/s actual ({efficiency:.1f}%) {status}")
    
    # Recommendations
    print("\n💡 RECOMMENDATIONS:")
    
    max_generation_rate = max(r['events_per_second'] for r in generation_results.values())
    print(f"   - Maximum generation rate: {max_generation_rate:,.0f} events/second")
    
    successful_streaming = [rate for rate, result in streaming_results.items() if result['efficiency'] >= 0.9]
    if successful_streaming:
        max_streaming = max(successful_streaming)
        print(f"   - Recommended max streaming rate: {max_streaming:,} events/second")
    
    if max_generation_rate >= 10000:
        print("   - ✅ System capable of 10K+ events/second")
        print("   - 🚀 Ready for high-performance production workloads")
    elif max_generation_rate >= 1000:
        print("   - ✅ System capable of 1K+ events/second")
        print("   - 📈 Consider CPU/memory upgrades for 10K+ target")
    else:
        print("   - ⚠️  System may need optimization for high-throughput workloads")
        print("   - 💻 Consider hardware upgrades or code optimization")
    
    print(f"\n🎯 For 10,000 events/second target:")
    if 10000 in streaming_results:
        result = streaming_results[10000]
        if result['efficiency'] >= 0.8:
            print("   - ✅ Target achievable with current system")
        else:
            print("   - ⚠️  Target may require system optimization")
    else:
        print("   - 🧪 Run test with --rate 10000 to validate")

if __name__ == "__main__":
    try:
        run_comprehensive_performance_test()
    except KeyboardInterrupt:
        print("\n🛑 Performance tests interrupted")
    except Exception as e:
        print(f"\n❌ Performance test error: {e}")
        import traceback
        traceback.print_exc()