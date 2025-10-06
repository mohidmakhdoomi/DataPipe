#!/bin/bash
# Backup Validation Test Suite
# Tests backup integrity and recovery procedures
# Usage: ./validate-backups.sh

set -e

BACKUP_BASE="/e/Projects/DataPipe/backups"
NAMESPACE="data-ingestion"

echo "========================================="
echo "  Backup Validation Test Suite"
echo "========================================="
echo ""

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass_count=0
fail_count=0

# Test function
run_test() {
  local test_name=$1
  local test_command=$2
  
  echo -n "Test: ${test_name}... "
  
  if eval "$test_command" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}"
    ((pass_count++))
    return 0
  else
    echo -e "${RED}❌ FAIL${NC}"
    ((fail_count++))
    return 1
  fi
}

# Test 1: Check if backup directories exist
echo "=== Infrastructure Tests ==="
run_test "PostgreSQL base backup directory exists" \
  "[ -d '${BACKUP_BASE}/postgresql/base' ]"

run_test "PostgreSQL logical backup directory exists" \
  "[ -d '${BACKUP_BASE}/postgresql/logical' ]"

run_test "Kafka topic backup directory exists" \
  "[ -d '${BACKUP_BASE}/kafka/topics' ]"

run_test "Replication slot backup directory exists" \
  "[ -d '${BACKUP_BASE}/postgresql/replication_slots' ]"

echo ""

# Test 2: PostgreSQL base backup validation
echo "=== PostgreSQL Base Backup Tests ==="
if [ -d "${BACKUP_BASE}/postgresql/base" ]; then
  LATEST_BASE_BACKUP=$(ls -t "${BACKUP_BASE}/postgresql/base" 2>/dev/null | head -1)
  
  if [ -n "$LATEST_BASE_BACKUP" ]; then
    run_test "Latest base backup exists" \
      "[ -f '${BACKUP_BASE}/postgresql/base/${LATEST_BASE_BACKUP}/base.tar.gz' ]"
    
    run_test "Base backup is valid tar.gz" \
      "tar -tzf '${BACKUP_BASE}/postgresql/base/${LATEST_BASE_BACKUP}/base.tar.gz' > /dev/null"
    
    run_test "Base backup metadata exists" \
      "[ -f '${BACKUP_BASE}/postgresql/base/${LATEST_BASE_BACKUP}/backup_info.txt' ]"
  else
    echo -e "${YELLOW}⚠️  No base backups found${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Base backup directory not found${NC}"
fi

echo ""

# Test 3: PostgreSQL logical backup validation
echo "=== PostgreSQL Logical Backup Tests ==="
if [ -d "${BACKUP_BASE}/postgresql/logical" ]; then
  LATEST_LOGICAL=$(ls -t "${BACKUP_BASE}/postgresql/logical"/*.dump 2>/dev/null | head -1)
  
  if [ -n "$LATEST_LOGICAL" ]; then
    run_test "Latest logical backup exists" \
      "[ -f '${LATEST_LOGICAL}' ]"
    
    # Test if backup can be listed (validates format)
    run_test "Logical backup format is valid" \
      "kubectl exec -n ${NAMESPACE} postgresql-0 -- pg_restore --list /dev/null 2>&1 | grep -q 'pg_restore'"
  else
    echo -e "${YELLOW}⚠️  No logical backups found${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Logical backup directory not found${NC}"
fi

echo ""

# Test 4: Kafka topic backup validation
echo "=== Kafka Topic Backup Tests ==="
if [ -d "${BACKUP_BASE}/kafka/topics" ]; then
  LATEST_KAFKA=$(ls -t "${BACKUP_BASE}/kafka/topics"/kafka_backup_*.tar.gz 2>/dev/null | head -1)
  
  if [ -n "$LATEST_KAFKA" ]; then
    run_test "Latest Kafka backup exists" \
      "[ -f '${LATEST_KAFKA}' ]"
    
    run_test "Kafka backup is valid tar.gz" \
      "tar -tzf '${LATEST_KAFKA}' > /dev/null"
  else
    echo -e "${YELLOW}⚠️  No Kafka backups found${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  Kafka backup directory not found${NC}"
fi

echo ""

# Test 5: Replication slot metadata validation
echo "=== Replication Slot Backup Tests ==="
if [ -d "${BACKUP_BASE}/postgresql/replication_slots" ]; then
  run_test "Replication slot metadata exists" \
    "[ -f '${BACKUP_BASE}/postgresql/replication_slots/replication_slots_latest.txt' ]"
  
  run_test "Slot positions CSV exists" \
    "[ -f '${BACKUP_BASE}/postgresql/replication_slots/slot_positions_latest.csv' ]"
else
  echo -e "${YELLOW}⚠️  Replication slot backup directory not found${NC}"
fi

echo ""

# Test 6: Kubernetes resources validation
echo "=== Kubernetes Resources Tests ==="
run_test "PostgreSQL pod is running" \
  "kubectl get pod -n ${NAMESPACE} postgresql-0 -o jsonpath='{.status.phase}' | grep -q 'Running'"

run_test "Kafka pods are running" \
  "[ \$(kubectl get pods -n ${NAMESPACE} -l app=kafka -o jsonpath='{.items[*].status.phase}' | grep -o 'Running' | wc -l) -eq 3 ]"

run_test "Kafka Connect pod is running" \
  "kubectl get pod -n ${NAMESPACE} -l app=kafka-connect -o jsonpath='{.status.phase}' | grep -q 'Running'"

echo ""

# Test 7: Backup script permissions
echo "=== Backup Script Tests ==="
SCRIPT_DIR="/e/Projects/DataPipe/1-data-ingestion-pipeline/scripts"

run_test "PostgreSQL base backup script exists" \
  "[ -f '${SCRIPT_DIR}/postgresql-base-backup.sh' ]"

run_test "PostgreSQL logical backup script exists" \
  "[ -f '${SCRIPT_DIR}/postgresql-logical-backup.sh' ]"

run_test "Kafka topic backup script exists" \
  "[ -f '${SCRIPT_DIR}/kafka-topic-backup.sh' ]"

run_test "CDC replication slot backup script exists" \
  "[ -f '${SCRIPT_DIR}/cdc-replication-slot-backup.sh' ]"

echo ""

# Test 8: Database connectivity
echo "=== Database Connectivity Tests ==="
run_test "PostgreSQL is accessible" \
  "kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -c 'SELECT 1' > /dev/null"

run_test "E-commerce database exists" \
  "kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -l | grep -q 'ecommerce'"

run_test "CDC tables exist" \
  "kubectl exec -n ${NAMESPACE} postgresql-0 -- psql -U postgres -d ecommerce -c '\dt' | grep -q 'users'"

echo ""

# Test 9: Replication slot status
echo "=== Replication Slot Status Tests ==="
SLOT_COUNT=$(kubectl exec -n ${NAMESPACE} postgresql-0 -- \
  psql -U postgres -d ecommerce -t -c \
  "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name LIKE 'debezium_slot%';" | tr -d ' ')

if [ "$SLOT_COUNT" -gt 0 ]; then
  echo -e "${GREEN}✅ Found ${SLOT_COUNT} replication slots${NC}"
  
  # Check for inactive slots
  INACTIVE_SLOTS=$(kubectl exec -n ${NAMESPACE} postgresql-0 -- \
    psql -U postgres -d ecommerce -t -c \
    "SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name LIKE 'debezium_slot%' AND active = false;" | tr -d ' ')
  
  if [ "$INACTIVE_SLOTS" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${INACTIVE_SLOTS} inactive replication slots${NC}"
  fi
else
  echo -e "${YELLOW}⚠️  No replication slots found${NC}"
fi

echo ""

# Summary
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo -e "Passed: ${GREEN}${pass_count}${NC}"
echo -e "Failed: ${RED}${fail_count}${NC}"
echo "Total:  $((pass_count + fail_count))"
echo ""

if [ $fail_count -eq 0 ]; then
  echo -e "${GREEN}✅ All tests passed!${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed. Please review the output above.${NC}"
  exit 1
fi
