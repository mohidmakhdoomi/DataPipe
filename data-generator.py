#!/usr/bin/env python3
"""
Data Generator: Performance Benchmarking
Enhanced performance benchmark with latency measurement
"""

import time
import psycopg2
import threading
import statistics
import sys
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
import argparse
import functools

# Configuration
POSTGRES_HOST = "localhost"  # Direct connection via NodePort
POSTGRES_PORT = 5432  # NodePort mapped from kind-config.yaml
POSTGRES_DB = "ecommerce"
POSTGRES_USER = "postgres"
POSTGRES_PASSWORD = "postgres_password"  # Correct password from secrets
# target_rate = 1000  # events per second
# duration = 60  # seconds
LOG_DIR = os.environ.get("LOG_DIR", "./logs/resource-logs")


def log(message):
    """Log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Data Generator : {message}")

    # Also write to log file (handle Unicode encoding)
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(f"{LOG_DIR}/data-generator.log", "a", encoding="utf-8") as f:
        try:
            f.write(f"[{timestamp}] Data Generator : {message}\n")
        except UnicodeEncodeError:
            # Fallback: replace Unicode characters with ASCII
            ascii_message = (
                message.replace("❌", "[FAIL]")
                .replace("✅", "[PASS]")
                .replace("⚠️", "[WARN]")
                .replace("⏳", "[WAIT]")
            )
            f.write(f"[{timestamp}] Data Generator : {ascii_message}\n")


def setup_database():
    """Set up connection"""
    log("Setting up connection to database...")

    try:
        conn = psycopg2.connect(
            host=POSTGRES_HOST,
            port=POSTGRES_PORT,
            database=POSTGRES_DB,
            user=POSTGRES_USER,
            password=POSTGRES_PASSWORD,
            connect_timeout=10,
        )
        cur = conn.cursor()
        
        log("✅ DB connection ready")
        return conn, cur

    except Exception as e:
        log(f"❌ Database connection failed: {e}")
        return None, None


def benchmark_performance(target_rate, duration):
    """Run the performance benchmark"""
    log(
        f"Starting performance benchmark: {target_rate} events/sec for {duration} seconds"
    )

    # Setup database connection
    conn, cur = setup_database()
    if not conn:
        return False

    batch_size = (target_rate // 50) if (target_rate >= 50) else 1

    # Performance tracking
    batch_count = 0
    latencies = []
    errors = 0
    start_time = time.time()

    # Thread-safe counters
    lock = threading.Lock()

    def insert_batch():
        nonlocal batch_count, errors

        try:
            # Create batch with source timestamps for latency measurement
            batch_start = time.time()

            cur.execute(
                f"""
                INSERT INTO perf_test (email, first_name, last_name) 
                SELECT
                    'user_' || subquery.uuid || '_{int(batch_start * 1000)}@example.com',
                    'First_' || subquery.uuid,
                    'Last_' || subquery.uuid
                    FROM (SELECT generate_series(1, {batch_size}) as uuid) AS subquery;
                """
            )
            conn.commit()

            with lock:
                latencies.append((time.time() - batch_start) * 1000)
                batch_count += 1

        except Exception as e:
            with lock:
                errors += 1
            log(f"⚠️  Batch insert error: {e}")

    log("Starting load generation...")

    # Run benchmark with rate limiting
    with ThreadPoolExecutor(max_workers=10) as executor:

        while time.time() - start_time < duration:
            batch_start_time = time.time()

            # Submit batch
            executor.submit(insert_batch)

            # Rate limiting - aim for target_rate events per second
            # Each batch has batch_size events, so we need target_rate/batch_size batches per second
            # Then adjust target_batch_interval by 2% to account for expected overhead/difference
            target_batch_interval = 0.98 / (target_rate / batch_size)

            elapsed = time.time() - batch_start_time
            if elapsed < target_batch_interval:
                time.sleep(target_batch_interval - elapsed)

    total_time = time.time() - start_time

    # Wait for all batches to complete
    log("Waiting for all batches to complete...")
    time.sleep(5)

    events_sent = batch_count * batch_size
    actual_rate = events_sent / total_time if total_time > 0 else 0

    # Calculate latency statistics
    if latencies:
        avg_latency = statistics.mean(latencies)
        p50_latency = statistics.median(latencies)
        p95_latency = (
            statistics.quantiles(latencies, n=20)[18]
            if len(latencies) > 20
            else max(latencies)
        )
        p99_latency = (
            statistics.quantiles(latencies, n=100)[98]
            if len(latencies) > 100
            else max(latencies)
        )
    else:
        avg_latency = p50_latency = p95_latency = p99_latency = 0

    # Results
    log("\n=== Performance Benchmark Results ===")
    log(f"Events sent: {events_sent}")
    log(f"Duration: {total_time:.2f} seconds")
    log(f"Actual rate: {actual_rate:.2f} events/sec")
    log(f"Target achieved: {'✅ YES' if actual_rate >= target_rate else '❌ NO'}")
    log(f"Errors: {errors}")
    log(f"Average batch latency: {avg_latency:.2f}ms")
    log(f"P50 batch latency: {p50_latency:.2f}ms")
    log(f"P95 batch latency: {p95_latency:.2f}ms")
    log(f"P99 batch latency: {p99_latency:.2f}ms")
    log(f"Latency target (<500ms avg): {'✅ YES' if avg_latency < 500 else '❌ NO'}")

    # Write detailed results to file
    results_file = f"{LOG_DIR}/performance-results.txt"
    with open(results_file, "w") as f:
        f.write("Performance Benchmark Results\n")
        f.write("============================\n")
        f.write(f"Events sent: {events_sent}\n")
        f.write(f"Duration: {total_time:.2f} seconds\n")
        f.write(f"Actual rate: {actual_rate:.2f} events/sec\n")
        f.write(f"Target rate: {target_rate} events/sec\n")
        f.write(f"Rate achieved: {'YES' if actual_rate >= target_rate else 'NO'}\n")
        f.write(f"Errors: {errors}\n")
        f.write(f"Average batch latency: {avg_latency:.2f}ms\n")
        f.write(f"P50 batch latency: {p50_latency:.2f}ms\n")
        f.write(f"P95 batch latency: {p95_latency:.2f}ms\n")
        f.write(f"P99 batch latency: {p99_latency:.2f}ms\n")
        f.write(f"Latency target achieved (<500ms avg): {'YES' if avg_latency < 500 else 'NO'}\n")

    log(f"Detailed results written to: {results_file}")

    # Cleanup
    conn.close()

    # Success criteria: rate >= target_rate events/sec AND average latency < 500ms
    success = actual_rate >= target_rate and avg_latency < 500 and errors == 0

    if success:
        log("✅ Completed successfully - performance targets achieved")
    else:
        log("❌ Failed - performance targets not met")

    return success


def main():
    """Main execution function"""

    log("=== Starting Data Generator: Performance Benchmarking ===")

    def range_type(astr, min=1, max=100):
        value = int(astr)
        if min <= value <= max:
            return value
        else:
            raise argparse.ArgumentTypeError('value not in range %s-%s'%(min,max))
    
    parser = argparse.ArgumentParser(description='Query S3 Parquet files from data ingestion pipeline')
    parser.add_argument('--rate', required=True, type=functools.partial(range_type, min=1, max=15000),  default=1000, metavar="[1-15000]", help='Target rate as events per second')
    parser.add_argument('--duration', required=True, type=functools.partial(range_type, min=10, max=10800), default=60, metavar="[10-10800]", help='Duration of generation as seconds')
    
    args = parser.parse_args()

    try:
        success = benchmark_performance(args.rate, args.duration)
        sys.exit(0 if success else 1)

    except Exception as e:
        log(f"❌ Failed with exception: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
