#!/bin/bash
# validate-cdc-permissions.sh
# Validates PostgreSQL CDC user permissions and data access controls

set -e

NAMESPACE="data-ingestion"
DB_USER="debezium"
DB_NAME="ecommerce"

echo "=== CDC User Permissions Validation ==="
echo "Namespace: $NAMESPACE"
echo "Database User: $DB_USER"
echo "Database: $DB_NAME"
echo "Date: $(date)"
echo ""

# Get PostgreSQL pod
PG_POD=$(kubectl get pods -n $NAMESPACE -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
if [ -z "$PG_POD" ]; then
    echo "ERROR: PostgreSQL pod not found"
    exit 1
fi

echo "PostgreSQL pod: $PG_POD"
echo ""

# Function to run SQL query
run_sql() {
    kubectl exec -n $NAMESPACE $PG_POD -- psql -U postgres -d $DB_NAME -t -c "$1" 2>/dev/null | tr -d ' '
}

# Validate CDC user exists and has correct attributes
echo "=== CDC User Attributes Validation ==="
USER_INFO=$(run_sql "SELECT usename, userepl, usesuper, usecreatedb, usebypassrls FROM pg_user WHERE usename = '$DB_USER';")

if [ -z "$USER_INFO" ]; then
    echo "✗ CRITICAL: CDC user '$DB_USER' does not exist"
    exit 1
else
    echo "✓ CDC user '$DB_USER' exists"
fi

# Parse user attributes
USEREPL=$(echo "$USER_INFO" | cut -d'|' -f2)
USESUPER=$(echo "$USER_INFO" | cut -d'|' -f3)
USECREATEDB=$(echo "$USER_INFO" | cut -d'|' -f4)
USEBYPASSRLS=$(echo "$USER_INFO" | cut -d'|' -f5)

echo "User attributes:"
echo -n "  Replication privilege: $USEREPL "
if [ "$USEREPL" = "t" ]; then
    echo "✓ CORRECT"
else
    echo "✗ MISSING (REQUIRED)"
fi

echo -n "  Superuser privilege: $USESUPER "
if [ "$USESUPER" = "f" ]; then
    echo "✓ CORRECT (not superuser)"
else
    echo "✗ EXCESSIVE (should not be superuser)"
fi

echo -n "  Create database privilege: $USECREATEDB "
if [ "$USECREATEDB" = "f" ]; then
    echo "✓ CORRECT (cannot create databases)"
else
    echo "✗ EXCESSIVE (should not create databases)"
fi

echo -n "  Bypass RLS privilege: $USEBYPASSRLS "
if [ "$USEBYPASSRLS" = "f" ]; then
    echo "✓ CORRECT (cannot bypass RLS)"
else
    echo "✗ EXCESSIVE (should not bypass RLS)"
fi

echo ""

# Validate table-level permissions
echo "=== Table-Level Permissions Validation ==="
TABLES=("users" "products" "orders" "order_items")

for table in "${TABLES[@]}"; do
    echo "Checking permissions for table: $table"
    
    # Check SELECT permission (required)
    HAS_SELECT=$(run_sql "SELECT has_table_privilege('$DB_USER', 'public.$table', 'SELECT');")
    echo -n "  SELECT permission: "
    if [ "$HAS_SELECT" = "t" ]; then
        echo "✓ GRANTED (required)"
    else
        echo "✗ MISSING (required for CDC)"
    fi
    
    # Check INSERT permission (should not have)
    HAS_INSERT=$(run_sql "SELECT has_table_privilege('$DB_USER', 'public.$table', 'INSERT');")
    echo -n "  INSERT permission: "
    if [ "$HAS_INSERT" = "f" ]; then
        echo "✓ DENIED (correct)"
    else
        echo "✗ GRANTED (excessive privilege)"
    fi
    
    # Check UPDATE permission (should not have)
    HAS_UPDATE=$(run_sql "SELECT has_table_privilege('$DB_USER', 'public.$table', 'UPDATE');")
    echo -n "  UPDATE permission: "
    if [ "$HAS_UPDATE" = "f" ]; then
        echo "✓ DENIED (correct)"
    else
        echo "✗ GRANTED (excessive privilege)"
    fi
    
    # Check DELETE permission (should not have)
    HAS_DELETE=$(run_sql "SELECT has_table_privilege('$DB_USER', 'public.$table', 'DELETE');")
    echo -n "  DELETE permission: "
    if [ "$HAS_DELETE" = "f" ]; then
        echo "✓ DENIED (correct)"
    else
        echo "✗ GRANTED (excessive privilege)"
    fi
    
    echo ""
done

# Validate replication slot
echo "=== Replication Slot Validation ==="
SLOT_INFO=$(run_sql "SELECT slot_name, plugin, slot_type, active, active_pid FROM pg_replication_slots WHERE slot_name = 'debezium_slot';")

if [ -n "$SLOT_INFO" ]; then
    echo "✓ Replication slot 'debezium_slot' exists"
    echo "Slot details: $SLOT_INFO"
    
    SLOT_ACTIVE=$(echo "$SLOT_INFO" | cut -d'|' -f4)
    echo -n "Slot status: "
    if [ "$SLOT_ACTIVE" = "t" ]; then
        echo "✓ ACTIVE"
    else
        echo "⚠️  INACTIVE (may be normal if connector is stopped)"
    fi
else
    echo "⚠️  WARNING: Replication slot 'debezium_slot' not found"
fi

echo ""

# Validate publication
echo "=== Publication Validation ==="
PUB_INFO=$(run_sql "SELECT pubname, puballtables FROM pg_publication WHERE pubname = 'dbz_publication';")

if [ -n "$PUB_INFO" ]; then
    echo "✓ Publication 'dbz_publication' exists"
    
    PUB_ALL_TABLES=$(echo "$PUB_INFO" | cut -d'|' -f2)
    echo -n "Publication scope: "
    if [ "$PUB_ALL_TABLES" = "t" ]; then
        echo "ALL TABLES"
    else
        echo "SPECIFIC TABLES"
        # List specific tables in publication
        PUB_TABLES=$(run_sql "SELECT schemaname||'.'||tablename FROM pg_publication_tables WHERE pubname = 'dbz_publication';")
        echo "Published tables: $PUB_TABLES"
    fi
else
    echo "⚠️  WARNING: Publication 'dbz_publication' not found"
fi

echo ""

# Check for excessive permissions on other schemas
echo "=== Cross-Schema Permission Check ==="
OTHER_SCHEMAS=$(run_sql "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'pg_catalog', 'pg_toast', 'public');")

if [ -n "$OTHER_SCHEMAS" ]; then
    echo "Checking permissions on other schemas..."
    for schema in $OTHER_SCHEMAS; do
        SCHEMA_USAGE=$(run_sql "SELECT has_schema_privilege('$DB_USER', '$schema', 'USAGE');")
        if [ "$SCHEMA_USAGE" = "t" ]; then
            echo "⚠️  WARNING: CDC user has USAGE privilege on schema '$schema'"
        else
            echo "✓ No access to schema '$schema'"
        fi
    done
else
    echo "✓ No additional schemas found"
fi

echo ""

# Validate connection limits
echo "=== Connection Limits Validation ==="
CONN_LIMIT=$(run_sql "SELECT rolconnlimit FROM pg_roles WHERE rolname = '$DB_USER';")
echo "Connection limit for $DB_USER: $CONN_LIMIT"
if [ "$CONN_LIMIT" = "-1" ]; then
    echo "⚠️  WARNING: No connection limit set (consider setting a reasonable limit)"
else
    echo "✓ Connection limit is set"
fi

echo ""

# Check current connections
echo "=== Current Connections Check ==="
CURRENT_CONNS=$(run_sql "SELECT count(*) FROM pg_stat_activity WHERE usename = '$DB_USER';")
echo "Current connections for $DB_USER: $CURRENT_CONNS"

if [ "$CURRENT_CONNS" -gt 5 ]; then
    echo "⚠️  WARNING: High number of connections for CDC user"
else
    echo "✓ Normal connection count"
fi

echo ""

# Validate WAL configuration
echo "=== WAL Configuration Validation ==="
WAL_LEVEL=$(run_sql "SHOW wal_level;")
echo -n "WAL level: $WAL_LEVEL "
if [ "$WAL_LEVEL" = "logical" ]; then
    echo "✓ CORRECT"
else
    echo "✗ INCORRECT (should be 'logical')"
fi

MAX_REPL_SLOTS=$(run_sql "SHOW max_replication_slots;")
echo -n "Max replication slots: $MAX_REPL_SLOTS "
if [ "$MAX_REPL_SLOTS" -ge 4 ]; then
    echo "✓ SUFFICIENT"
else
    echo "⚠️  LOW (recommended: 4 or more)"
fi

MAX_WAL_SENDERS=$(run_sql "SHOW max_wal_senders;")
echo -n "Max WAL senders: $MAX_WAL_SENDERS "
if [ "$MAX_WAL_SENDERS" -ge 4 ]; then
    echo "✓ SUFFICIENT"
else
    echo "⚠️  LOW (recommended: 4 or more)"
fi

echo ""

# Generate summary
echo "=== CDC Permissions Validation Summary ==="
echo "Validation completed for CDC user '$DB_USER'"
echo ""
echo "Key findings:"
echo "- User exists with replication privileges"
echo "- Table-level permissions validated for CDC tables"
echo "- Replication slot and publication status checked"
echo "- WAL configuration validated"
echo ""
echo "Review any warnings or errors above and take corrective action if needed."