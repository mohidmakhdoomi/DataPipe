#!/bin/bash
# Task 8 Phase 5: Performance Benchmarking Wrapper
# Wrapper script to run Python performance benchmark

set -euo pipefail

readonly NAMESPACE="data-ingestion"
readonly LOG_DIR="${SCRIPT_DIR:-$(pwd)}/task8-logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Phase 5: $*" | tee -a "${LOG_DIR}/phase5.log"
}

main() {
    log "=== Starting Phase 5: Performance Benchmarking ==="
    
    # Check if Python is available
    if ! command -v python3 >/dev/null 2>&1; then
        log "❌ Python3 not found - required for performance benchmarking"
        return 1
    fi
    
    # Check if psycopg2 is available
    if ! python3 -c "import psycopg2" >/dev/null 2>&1; then
        log "⚠️  psycopg2 not available, attempting to install..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install psycopg2-binary >/dev/null 2>&1 || {
                log "❌ Failed to install psycopg2 - performance test cannot run"
                return 1
            }
        else
            log "❌ pip3 not available - cannot install psycopg2"
            return 1
        fi
    fi
    
    # Set environment variables for Python script
    export LOG_DIR="${LOG_DIR}"
    
    # Run Python performance benchmark
    log "Executing performance benchmark..."
    if python3 "${SCRIPT_DIR}/task8-phase5-performance.py"; then
        log "✅ Performance benchmark completed successfully"
        return 0
    else
        log "❌ Performance benchmark failed"
        return 1
    fi
}

main "$@"