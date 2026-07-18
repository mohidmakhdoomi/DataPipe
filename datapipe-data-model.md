# DataPipe — Canonical Data Model

**Status**: Governing document (per remediation program, `datapipe-remediation-plan.md` §11)
**Date**: 2026-07-18
**Purpose**: The single definition of every entity, key, type, and naming convention that flows through DataPipe. When any layer's schema conflicts with this document, **this document wins** and the layer is considered broken.

**Governing principle**: one schema per entity, defined once, carried everywhere. Humans author exactly two things — the OLTP DDL and the `UserEvent` Avro schema. Everything downstream (Kafka, Iceberg bronze/silver, ClickHouse, Snowflake) is a projection of those.

---

## 1. Global conventions

| Concern | Convention | Rationale |
|---|---|---|
| Entity IDs | **Integers end-to-end** (`SERIAL` in PG → `long` in Avro/Iceberg → `UInt64`/`Int64` in ClickHouse → `NUMBER`/`BIGINT` in Snowflake). **No UUID types for joinable IDs** anywhere. | Kills the spec's UUID/integer drift and the "UUID→STRING" special cases. |
| Generated (non-joinable) IDs | `event_id`, `session_id` are UUID **strings**. They never join to OLTP data. | Only place UUIDs are allowed. |
| Timestamps | UTC everywhere. Transport as epoch-micros (Avro `timestamp-micros` via Debezium `time.precision.mode=adaptive_time_microseconds`); `DateTime64(3)` in ClickHouse; `TIMESTAMP_NTZ` in Snowflake. Field names: `created_at`/`updated_at` (OLTP), `event_time` (events), `__ts_ms`/`__source_ts_ms` (lineage). | Mixed precision/timezones were a spec-level ambiguity. |
| Money | `DECIMAL(10,2)` everywhere. Debezium `decimal.handling.mode=precise` (**not** the current `string`). | Money as strings breaks aggregation in every engine. |
| Lineage fields | `__op` (c/u/d/r), `__ts_ms`, `__source_ts_ms`, `__source_lsn`, `__deleted` — preserved through the SMT chain and present in **all bronze CDC tables**; `__source_lsn` carried to silver and Snowflake Raw. | Any row in any layer traces back to a WAL position. |
| Naming | Bronze: `ecommerce_raw.<entity>`; silver: `ecommerce.<entity>`; Snowflake: `ECOMMERCE_DW.raw/staging/marts.*`; ClickHouse: `<entity>_realtime`. Behavioral entities are `user_events`/`user_sessions` — the name `transactions` is **retired** (collided with `orders`). | Same name = same thing, in every layer. |

---

## 2. Domain 1 — Transactional (CDC path)

### 2.1 PostgreSQL OLTP (source of truth)

Defined in `1-data-ingestion-pipeline/task4-postgresql-statefulset.yaml`. Two columns are **added** to `users` (see §6 ripple R1):

```sql
users (
    id            SERIAL PRIMARY KEY,
    email         VARCHAR(255) UNIQUE NOT NULL,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    tier          VARCHAR(20) NOT NULL DEFAULT 'bronze'
                  CHECK (tier IN ('bronze','silver','gold','platinum')),
    is_active     BOOLEAN NOT NULL DEFAULT true,
    created_at    TIMESTAMP(3) DEFAULT NOW(),
    updated_at    TIMESTAMP(3) DEFAULT NOW()
)
products (id, name, description, price DECIMAL(10,2), stock_quantity, category, created_at, updated_at)
orders   (id, user_id FK, status ENUM(pending,processing,shipped,delivered,cancelled),
          total_amount DECIMAL(10,2), shipping_address, created_at, updated_at)
order_items (id, order_id FK, product_id FK, quantity, unit_price DECIMAL(10,2), created_at, updated_at)
```

- **`tier` is an OLTP attribute** (CRM-style, slowly changing). The generator assigns it with the business distribution (bronze 60% / silver 25% / gold 12% / platinum 3%) and occasionally updates it. This is the *only* authoritative home for tier — every downstream tier is a projection of this column.
- `is_active` supports soft-deactivation scenarios (and the speed layer's enrichment filter).

### 2.2 Kafka (Debezium CDC)

- Topics: `postgres.public.{users,products,orders,order_items}` (unchanged).
- Avro via Schema Registry (**FULL** compatibility after R2).
- SMT chain must preserve `__op`, `__ts_ms`, `__source_ts_ms`, `__source_lsn`, `__deleted` (R2 fixes the current delete-erasing chain).
- `decimal.handling.mode=precise` (R2).

### 2.3 Iceberg bronze — `ecommerce_raw.*`

Append-only CDC event log, written by the Iceberg sink connector (append mode). One table per OLTP table: `ecommerce_raw.{users,products,orders,order_items}`.

- Columns: full row image + `__op`, `__ts_ms`, `__source_ts_ms`, `__source_lsn`, `__deleted`.
- Partition: `hours(__source_ts_ms)` transform. Immutable; replay + audit via Iceberg time travel.

### 2.4 Iceberg silver — `ecommerce.*`

Current-state mirrors, built by a Spark `MERGE INTO` job reading bronze: `ecommerce.{users,products,orders,order_items}`.

- Columns: OLTP columns + `__source_lsn` (lineage) + `merged_at`. Deletes **applied** (rows removed). Dedupe on `(id, __source_lsn)`.
- This is where batch data-quality validation lives.

### 2.5 Snowflake — `ECOMMERCE_DW`

- **Raw** (`raw.*`): mirrors of the *silver* tables (not bronze) + load metadata (`loaded_at`, `batch_id`, `__source_lsn`). Clustering per batch spec.
- **Staging** (`staging.*`): enhanced/typed models per batch spec (`users_enhanced`, etc.). `customer_tier` here is a projection of `users.tier`, not a re-derivation.
- **Marts** (`marts.*`): `daily_business_metrics`, `customer_tier_analytics`, `product_performance`, `customer_analytics` per batch spec; dbt-managed, incremental.

---

## 3. Domain 2 — Behavioral (event path)

### 3.1 Canonical `UserEvent` schema (authored once, in Schema Registry)

```json
{
  "type": "record",
  "name": "UserEvent",
  "namespace": "datapipe.events",
  "fields": [
    {"name": "event_id",   "type": "string", "doc": "UUID, generated, never joined"},
    {"name": "event_type", "type": {"type": "enum", "name": "EventType", "symbols": [
      "PAGE_VIEW", "PRODUCT_VIEW", "SEARCH", "ADD_TO_CART", "PURCHASE",
      "REMOVE_FROM_CART", "CHECKOUT_START", "LOGIN", "LOGOUT"]}},
    {"name": "event_time", "type": {"type": "long", "logicalType": "timestamp-micros"}},
    {"name": "user_id",    "type": "long", "doc": "always present; matches users.id"},
    {"name": "session_id", "type": "string", "doc": "generator-assigned UUID; identical sessionization key for speed and batch"},
    {"name": "product_id", "type": ["null", "long"], "default": null},
    {"name": "order_id",   "type": ["null", "long"], "default": null},
    {"name": "amount",     "type": ["null", {"type": "bytes", "logicalType": "decimal",
                                    "precision": 10, "scale": 2}], "default": null},
    {"name": "properties", "type": {"type": "map", "values": "string"}, "default": {}}
  ]
}
```

### 3.2 Field requirements per event type (generator contract)

| event_type | product_id | order_id | amount | Notes |
|---|---|---|---|---|
| PAGE_VIEW | — | — | — | |
| PRODUCT_VIEW | required | — | — | |
| SEARCH | — | — | — | `properties.query` set |
| ADD_TO_CART | required | — | — | |
| REMOVE_FROM_CART | required | — | — | |
| CHECKOUT_START | — | — | — | |
| **PURCHASE** | — | **required** | **required** | `order_id` and `amount` **must equal** the corresponding `orders.id`/`orders.total_amount` — this is the reconciliation linchpin |
| LOGIN / LOGOUT | — | — | — | |

### 3.3 Kafka

- One topic: `events.user_events`, keyed by `user_id` (ordering per user), Avro, FULL compatibility. Partition count sized for the 10k/s target in R7.

### 3.4 Iceberg

- Bronze: `ecommerce_raw.user_events` — append-only, same Iceberg sink, partition `hours(event_time)`.
- Silver: `ecommerce.user_sessions` — batch sessionization keyed on `session_id` (comparable to speed-layer sessions by construction).

### 3.5 ClickHouse (speed layer)

- `user_events_realtime`: columns per `UserEvent`; IDs as `UInt64` (**not UUID**), `event_time DateTime64(3)`, `amount Decimal(10,2)`, enums as `LowCardinality(String)`, `properties` as `Map(String,String)` or JSON. Engine: `MergeTree` (no Keeper — see architecture review #4), partitioned monthly.
- `user_sessions_realtime`: stream-computed sessions keyed by `session_id`.
- Materialized views (`SummingMergeTree`, queried with `GROUP BY`): `conversion_funnel_mv`, `user_tier_performance_mv`, `product_performance_mv`, **`purchase_reconciliation_mv`** (per-date orders/revenue/AOV from PURCHASE events — the speed side of reconciliation).
- **`transactions_realtime` is dropped** — purchases are `PURCHASE` events.
- **Tier enrichment reads the CDC stream, not PostgreSQL**: the streaming job maintains its tier cache from the `postgres.public.users` topic (which carries `tier` after R1/R2). No cross-cluster OLTP reads.

---

## 4. Cross-domain linkage

The only join keys between the two domains — everything else is coincidence:

| Key | Domain 1 | Domain 2 | Rule |
|---|---|---|---|
| `user_id` | `users.id` | `UserEvent.user_id` | always present on events |
| `product_id` | `products.id` | `UserEvent.product_id` | required on product events |
| `order_id` | `orders.id` | `UserEvent.order_id` (PURCHASE) | generator emits the event and the OLTP rows as one correlated act |

**Reconciliation keys**: per-date aggregates over `orders` (via `order_items`) in Snowflake marts vs. PURCHASE events in ClickHouse — `active_customers` (distinct `user_id`), `total_orders` (distinct `order_id`), `total_revenue` (sum `amount`/`total_amount`), `avg_order_value`. Tolerances: 5% warn / 10% critical.

---

## 5. Per-layer entity inventory

| Entity | PG | Kafka topic | Bronze | Silver | ClickHouse | Snowflake |
|---|---|---|---|---|---|---|
| users | ✅ public.users | postgres.public.users | ecommerce_raw.users | ecommerce.users | (tier cache) | raw/staging/marts |
| products | ✅ public.products | postgres.public.products | ecommerce_raw.products | ecommerce.products | (join via MVs) | raw/staging/marts |
| orders | ✅ public.orders | postgres.public.orders | ecommerce_raw.orders | ecommerce.orders | — | raw/staging/marts |
| order_items | ✅ public.order_items | postgres.public.order_items | ecommerce_raw.order_items | ecommerce.order_items | — | raw/staging/marts |
| user events | — (generator) | events.user_events | ecommerce_raw.user_events | — | user_events_realtime + MVs | staging/marts (via silver sessions) |
| user sessions | — | — | — | ecommerce.user_sessions | user_sessions_realtime | marts |

---

## 6. Ripple effects on the remediation workstreams

- **R1 (generator rewrite)**: add `tier`/`is_active` to OLTP DDL + sample data; assign tiers per 60/25/12/3 distribution; implement the §3.2 contract (correlated PURCHASE ↔ orders/order_items with shared `order_id`/`amount`); produce `UserEvent` Avro to `events.user_events`; fix the bogus FK generation.
- **R2 (CDC correctness)**: `decimal.handling.mode=precise`; preserve `__deleted` + `__op` through the SMT chain (required by silver merge); FULL compatibility (the `users` DDL change is itself a schema evolution — must pass through Schema Registry cleanly).
- **R3 (bronze+silver)**: bronze is **six** tables, not four — `ecommerce_raw.user_events` rides the same sink; silver includes `ecommerce.user_sessions` (batch sessionization on `session_id`).
- **R4 (batch)**: Snowflake Raw mirrors silver; `customer_tier` projects `users.tier`; dbt staging models updated for new columns.
- **R5 (speed)**: ClickHouse schema per §3.5 (integer IDs, no `transactions_realtime`, plain `MergeTree`); tier enrichment from CDC stream, not PostgreSQL.
- **R6 (reconciliation)**: keys per §4 — no UUID alignment step needed anymore (spec's T9/T15 UUID→STRING notes are void).

## 7. Explicitly rejected alternatives

- **Derived tier (compute in batch from spend)**: leaves the speed layer with no realtime tier source. Rejected — tier lives in OLTP.
- **UUIDs everywhere**: churn in PG DDL and all existing data for zero local benefit. Rejected.
- **Separate topic per event type**: 9 topics/schemas to manage vs. one; ordering per user harder. Rejected.
- **Keeping `transactions_realtime`**: name collision with `orders`, duplicate storage of PURCHASE events. Rejected.
