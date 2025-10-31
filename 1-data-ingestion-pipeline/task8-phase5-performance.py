#!/usr/bin/env python3
"""
Task 8 Phase 5: Performance Benchmarking
Enhanced performance benchmark with latency measurement
Based on Gemini's technical guidance for accurate end-to-end latency measurement
"""

import time
import psycopg2
import threading
import statistics
import sys
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

# Configuration
POSTGRES_HOST = "localhost"  # Direct connection via NodePort
POSTGRES_PORT = 5432  # NodePort mapped from kind-config.yaml
POSTGRES_DB = "ecommerce"
POSTGRES_USER = "postgres"
POSTGRES_PASSWORD = "postgres_password"  # Correct password from secrets
TARGET_RATE = 1000  # events per second
DURATION = 60  # seconds
LOG_DIR = os.environ.get("LOG_DIR", "./logs/data-ingestion/task8-logs")


def log(message):
    """Log with timestamp"""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] [INFO] Phase 5: {message}")

    # Also write to log file (handle Unicode encoding)
    os.makedirs(LOG_DIR, exist_ok=True)
    try:
        with open(f"{LOG_DIR}/phase5.log", "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] Phase 5: {message}\n")
    except UnicodeEncodeError:
        # Fallback: replace Unicode characters with ASCII
        ascii_message = (
            message.replace("❌", "[FAIL]")
            .replace("✅", "[PASS]")
            .replace("⚠️", "[WARN]")
            .replace("⏳", "[WAIT]")
        )
        with open(f"{LOG_DIR}/phase5.log", "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] Phase 5: {ascii_message}\n")


def setup_database():
    """Set up performance test table"""
    log("Setting up performance test database...")

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

        # Create performance test table with timestamp for latency measurement
        cur.execute("""
            CREATE TABLE IF NOT EXISTS perf_test (
                id SERIAL PRIMARY KEY,
                data TEXT,
                source_timestamp BIGINT,  -- For latency measurement
                created_at TIMESTAMP(3) DEFAULT NOW()
            )
        """)

        # Clear any existing test data
        cur.execute("TRUNCATE TABLE perf_test")
        conn.commit()

        log("✅ Performance test table ready")
        return conn, cur

    except Exception as e:
        log(f"❌ Database setup failed: {e}")
        return None, None


def benchmark_performance():
    """Run the 1000 events/sec performance benchmark"""
    log(
        f"Starting performance benchmark: {TARGET_RATE} events/sec for {DURATION} seconds"
    )

    # Setup database connection
    conn, cur = setup_database()
    if not conn:
        return False

    # Performance tracking
    events_sent = 0
    latencies = []
    errors = 0
    start_time = time.time()

    # Thread-safe counters
    lock = threading.Lock()

    def insert_batch():
        nonlocal events_sent, errors
        batch_start = time.time()
        batch_size = 100

        try:
            # Create batch with source timestamps for latency measurement
            source_timestamp = int(time.time() * 1000)  # milliseconds
            values = [
                (f"perf_test_data_{i}_{source_timestamp}", source_timestamp)
                for i in range(batch_size)
            ]

            cur.executemany(
                "INSERT INTO perf_test (data, source_timestamp) VALUES (%s, %s)", values
            )
            conn.commit()

            batch_end = time.time()
            batch_latency = (batch_end - batch_start) * 1000  # Convert to ms

            with lock:
                latencies.append(batch_latency)
                events_sent += batch_size

        except Exception as e:
            with lock:
                errors += 1
            log(f"⚠️  Batch insert error: {e}")

    log("Starting load generation...")

    # Run benchmark with rate limiting
    with ThreadPoolExecutor(max_workers=10) as executor:
        batch_count = 0

        while time.time() - start_time < DURATION:
            batch_start_time = time.time()

            # Submit batch
            executor.submit(insert_batch)
            batch_count += 1

            # Rate limiting - aim for TARGET_RATE events per second
            # Each batch has 100 events, so we need TARGET_RATE/100 batches per second
            # Then increase batches_per_second by 10% to account for expected overhead/difference
            batches_per_second = 1.1 * (TARGET_RATE / 100)
            target_batch_interval = 1.0 / batches_per_second

            elapsed = time.time() - batch_start_time
            if elapsed < target_batch_interval:
                time.sleep(target_batch_interval - elapsed)

    # Wait for all batches to complete
    log("Waiting for all batches to complete...")
    time.sleep(5)

    total_time = time.time() - start_time
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
    log(f"Target achieved: {'✅ YES' if actual_rate >= TARGET_RATE else '❌ NO'}")
    log(f"Errors: {errors}")
    log(f"Average batch latency: {avg_latency:.2f}ms")
    log(f"P50 batch latency: {p50_latency:.2f}ms")
    log(f"P95 batch latency: {p95_latency:.2f}ms")
    log(f"P99 batch latency: {p99_latency:.2f}ms")
    log(f"Latency target (<500ms avg): {'✅ YES' if avg_latency < 500 else '❌ NO'}")

    # Write detailed results to file
    results_file = f"{LOG_DIR}/performance-results.txt"
    with open(results_file, "w") as f:
        f.write(f"Performance Benchmark Results\n")
        f.write(f"============================\n")
        f.write(f"Events sent: {events_sent}\n")
        f.write(f"Duration: {total_time:.2f} seconds\n")
        f.write(f"Actual rate: {actual_rate:.2f} events/sec\n")
        f.write(f"Target rate: {TARGET_RATE} events/sec\n")
        f.write(f"Rate achieved: {'YES' if actual_rate >= TARGET_RATE else 'NO'}\n")
        f.write(f"Errors: {errors}\n")
        f.write(f"Average batch latency: {avg_latency:.2f}ms\n")
        f.write(f"P50 batch latency: {p50_latency:.2f}ms\n")
        f.write(f"P95 batch latency: {p95_latency:.2f}ms\n")
        f.write(f"P99 batch latency: {p99_latency:.2f}ms\n")
        f.write(f"Latency target achieved: {'YES' if avg_latency < 500 else 'NO'}\n")

    log(f"Detailed results written to: {results_file}")

    # Cleanup
    conn.close()

    # Success criteria: rate >= 1000 events/sec AND average latency < 500ms
    success = actual_rate >= TARGET_RATE and avg_latency < 500 and errors == 0

    if success:
        log("✅ Phase 5 completed successfully - performance targets achieved")
    else:
        log("❌ Phase 5 failed - performance targets not met")

    return success


def main():
    """Main execution function"""
    log("=== Starting Phase 5: Performance Benchmarking ===")

    try:
        success = benchmark_performance()
        sys.exit(0 if success else 1)

    except Exception as e:
        log(f"❌ Phase 5 failed with exception: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
