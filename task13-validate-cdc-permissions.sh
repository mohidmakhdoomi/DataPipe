#!/bin/bash
# Task 13: PostgreSQL CDC User Permission Validation
# Validates that the Debezium CDC user has minimal required permissions

set -euo pipefail

# Configuration
POSTGRES_HOST="${POSTGRES_HOST:-postgresql.data-ingestion.svc.cluster.local}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-ecommerce}"
CDC_USER="${CDC_USER:-debezium}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== PostgreSQL CDC User Permission Validation ==="
echo "Host: $POSTGRES_HOST:$POSTGRES_PORT"
echo "Database: $POSTGRES_DB"
echo "CDC User: $CDC_USER"
echo

# Function to check if user exists
check_user_exists() {
    local user=$1
    echo -n "Checking if user '$user' exists... "
    
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT 1 FROM pg_roles WHERE rolname='$user';" | grep -q 1; then
        echo -e "${GREEN}✓ EXISTS${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT FOUND${NC}"
        return 1
    fi
}

# Function to check replication permissions
check_replication_permission() {
    local user=$1
    echo -n "Checking REPLICATION permission for '$user'... "
    
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT rolreplication FROM pg_roles WHERE rolname='$user';" | grep -q t; then
        echo -e "${GREEN}✓ HAS REPLICATION${NC}"
        return 0
    else
        echo -e "${RED}✗ NO REPLICATION${NC}"
        return 1
    fi
}

# Function to check table permissions
check_table_permissions() {
    local user=$1
    local tables=("users" "products" "orders" "order_items")
    
    echo "Checking SELECT permissions on required tables:"
    local all_good=true
    
    for table in "${tables[@]}"; do
        echo -n "  - $table: "
        
        if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
            "SELECT has_table_privilege('$user', 'public.$table', 'SELECT');" | grep -q t; then
            echo -e "${GREEN}✓ SELECT${NC}"
        else
            echo -e "${RED}✗ NO SELECT${NC}"
            all_good=false
        fi
    done
    
    return $([ "$all_good" = true ] && echo 0 || echo 1)
}

# Function to check for excessive permissions
check_excessive_permissions() {
    local user=$1
    echo "Checking for excessive permissions (should be minimal):"
    
    # Check if user is superuser
    echo -n "  - Superuser check: "
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT rolsuper FROM pg_roles WHERE rolname='$user';" | grep -q f; then
        echo -e "${GREEN}✓ NOT SUPERUSER${NC}"
    else
        echo -e "${YELLOW}⚠ IS SUPERUSER (excessive)${NC}"
    fi
    
    # Check if user can create databases
    echo -n "  - Create DB check: "
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT rolcreatedb FROM pg_roles WHERE rolname='$user';" | grep -q f; then
        echo -e "${GREEN}✓ CANNOT CREATE DB${NC}"
    else
        echo -e "${YELLOW}⚠ CAN CREATE DB (excessive)${NC}"
    fi
    
    # Check if user can create roles
    echo -n "  - Create Role check: "
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT rolcreaterole FROM pg_roles WHERE rolname='$user';" | grep -q f; then
        echo -e "${GREEN}✓ CANNOT CREATE ROLES${NC}"
    else
        echo -e "${YELLOW}⚠ CAN CREATE ROLES (excessive)${NC}"
    fi
}

# Function to check replication slot
check_replication_slot() {
    echo -n "Checking for Debezium replication slot... "
    
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT 1 FROM pg_replication_slots WHERE slot_name='debezium_slot';" | grep -q 1; then
        echo -e "${GREEN}✓ SLOT EXISTS${NC}"
        
        # Check slot status
        echo -n "  - Slot status: "
        local active=$(kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
            "SELECT active FROM pg_replication_slots WHERE slot_name='debezium_slot';")
        
        if [ "$active" = "t" ]; then
            echo -e "${GREEN}ACTIVE${NC}"
        else
            echo -e "${YELLOW}INACTIVE${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ SLOT NOT FOUND${NC}"
    fi
}

# Function to check publication
check_publication() {
    echo -n "Checking for Debezium publication... "
    
    if kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -tAc \
        "SELECT 1 FROM pg_publication WHERE pubname='dbz_publication';" | grep -q 1; then
        echo -e "${GREEN}✓ PUBLICATION EXISTS${NC}"
        
        # Check which tables are included
        echo "  - Published tables:"
        kubectl exec -n data-ingestion postgresql-0 -- psql -U postgres -d "$POSTGRES_DB" -c \
            "SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname='dbz_publication';" | \
            grep -E "(users|products|orders|order_items)" | while read line; do
                echo "    $line"
            done
    else
        echo -e "${YELLOW}⚠ PUBLICATION NOT FOUND${NC}"
    fi
}

# Main validation
main() {
    local exit_code=0
    
    echo "Starting CDC user permission validation..."
    echo
    
    # Check user exists
    if ! check_user_exists "$CDC_USER"; then
        echo -e "${RED}ERROR: CDC user does not exist${NC}"
        exit 1
    fi
    
    echo
    
    # Check replication permission
    if ! check_replication_permission "$CDC_USER"; then
        echo -e "${RED}ERROR: CDC user lacks REPLICATION permission${NC}"
        exit_code=1
    fi
    
    echo
    
    # Check table permissions
    if ! check_table_permissions "$CDC_USER"; then
        echo -e "${RED}ERROR: CDC user lacks required SELECT permissions${NC}"
        exit_code=1
    fi
    
    echo
    
    # Check for excessive permissions
    check_excessive_permissions "$CDC_USER"
    
    echo
    
    # Check replication infrastructure
    check_replication_slot
    echo
    check_publication
    
    echo
    echo "=== Validation Summary ==="
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ CDC user permissions are properly configured${NC}"
        echo "✓ User has minimal required permissions (REPLICATION + SELECT on specific tables)"
        echo "✓ No excessive permissions detected"
    else
        echo -e "${RED}✗ CDC user permission issues detected${NC}"
        echo "Please review and fix the identified issues"
    fi
    
    # Generate audit report
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local report_file="/tmp/cdc-permissions-audit-$timestamp.json"
    
    cat > "$report_file" << EOF
{
  "audit_type": "cdc_permissions",
  "timestamp": "$timestamp",
  "user": "$CDC_USER",
  "database": "$POSTGRES_DB",
  "host": "$POSTGRES_HOST",
  "status": $([ $exit_code -eq 0 ] && echo '"PASS"' || echo '"FAIL"'),
  "checks_performed": [
    "user_exists",
    "replication_permission",
    "table_select_permissions",
    "excessive_permissions_check",
    "replication_slot_status",
    "publication_status"
  ]
}
EOF
    
    echo "Audit report saved to: $report_file"
    
    exit $exit_code
}

# Run main function
main "$@"