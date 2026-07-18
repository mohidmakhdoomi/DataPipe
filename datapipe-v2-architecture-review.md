# DataPipe v2 — Architecture Review

**Status**: Draft
**Date**: 2026-07-18
**Subject**: Architectural critique of the original v2 plan, ordered by severity. Verification results against the v1 implementation are appended where checked. (The plan document has since been renamed `datapipe-remediation-plan.md` and reframed as a remediation program; its §11 addendum governs.)

---

## Critical seams

### 1. The Parquet → Iceberg hop does not exist

Inherited from v1, not fixed in the v2 report. The S3 Sink writes *plain Parquet directories* (`year=/month=/day=/hour=`). An Iceberg table requires Iceberg's own metadata layer (manifests, snapshots) — a `hadoop` catalog cannot read the sink output as a table. The v1 batch design's `Spark reads iceberg.ecommerce.*` therefore has no continuous producer. v2 must explicitly choose one of:

- a scheduled **Spark "Iceberg loader"** job (append new hourly partitions into the Iceberg tables, Airflow-triggered), or
- replace the S3 Sink connector with an **Iceberg sink connector**, making the archive *be* the Iceberg table (cleaner, one hop instead of two, but reopens the ingestion layer's "done" status).

### 2. Reconciliation compares two uncoordinated synthetic streams

v2 has the generator emit behavioral events (speed path) *and* OLTP changes (CDC path). ClickHouse aggregates the former; Snowflake the latter. Unless the generator deliberately correlates them — same order IDs, same amounts, `PURCHASE` events that exactly match `orders`/`order_items` rows with a shared ID — reconciliation will always diverge and the 5% tolerance alert becomes noise. The generator must emit causally-linked event pairs. This requirement is missing from the v2 report and belongs in W3.

### 3. "Exactly-once" is over-promised

G4 says "deliver exactly-once" while the report itself walks it back to effectively-once at sinks. Additional concrete issues:

- Debezium source is at-least-once by nature (redelivery after restart before offset flush).
- **v1 design bug**: `errors.tolerance` and DLQs do not work for *source* connectors. The `connect-dlq` configured on the Debezium connector is decorative; only the S3 Sink's `s3-sink-dlq` actually functions.
- Spark `foreachBatch` retries into ClickHouse duplicate rows unless relying on `ReplicatedMergeTree` block deduplication or `ReplacingMergeTree` with a version column.

G4 should be restated as "no silent loss; duplicates bounded and documented per hop", with dedupe keys carried in the event schema.

## Design bugs to fix

### 4. `ReplicatedMergeTree` with no Keeper

The ClickHouse spec uses replicated table engines but never deploys ZooKeeper or ClickHouse Keeper — replication is impossible without one (~1Gi + config). For single-node local dev, drop to plain `MergeTree` / `SummingMergeTree`.

### 5. `tasks.max=24` on a single 2Gi Connect worker

Matches partition count on paper, but each task carries its own consumer + Parquet writer buffers; 24 of them in 2Gi invites GC pressure exactly at 10k events/sec. Standard shape: 4–6 tasks each handling multiple partitions.

### 6. Unbudgeted control planes

The 25Gi v2 budget counts workloads only. Four kind clusters = four control planes + kube-system/CNI/CoreDNS per cluster — realistically 2–4Gi of the 26Gi before any budget line. Reserve explicitly or let W6's combined soak test arbitrate.

## Cross-cluster mechanism risks

### 7. NodePort + Docker container IPs is the most brittle discovery mechanism

Container IPs change on every kind restart / node recreate; `endpoints.yaml` regenerated at deploy time goes stale silently at runtime. More stable variant: kind `extraPortMappings` to fixed host ports + `host.docker.internal` (needs `extraHosts` on Linux). Same simplicity, far less drift. Kafka's advertised listeners must return an address routable from the *other cluster's pods* — the fiddliest part of the plan; spike it in W1.

### 8. The ingestion cluster is a hard dependency of everything

Schema Registry, Kafka, and PostgreSQL (the speed layer's tier-enrichment lookup reads it directly) all live there. Stop that cluster and the speed layer, batch loads, and orchestration DAGs all fail together. Acceptable for local dev, but should be stated as an accepted coupling.

## Smaller items

- **Session semantics mismatch**: speed spec sessions use `ProcessingTimeTimeout` while batch aggregates are event-time — reconciled per-date numbers will skew at boundaries. Pick event-time consistently or document a skew budget.
- **dbt `on_schema_change='fail'`** halts the daily DAG on any PostgreSQL schema evolution — "graceful schema evolution" then needs an Iceberg→Snowflake evolution runbook; FULL compatibility in Schema Registry only governs the Kafka hop.
- **Prometheus at 1.5Gi** while the design keeps 15d retention / 8GB TSDB — retention must be trimmed to the pod budget.
- **Hygiene**: `k8s.gcr.io/git-sync` is the frozen registry (use `registry.k8s.io`); S3 bucket names differ across specs (`datapipe-ingestion-*` vs `data-s3-bucket`); `SummingMergeTree` MVs need `GROUP BY` at query time (or `FINAL`) or reconciliation reads partial sums.

## Net assessment

Topology, budgeting, and workstream sequencing are sound. But seams #1 and #2 mean the plan can produce a system where every component is green and the end-to-end story still does not work. W1's spike list should start with the Kafka cross-cluster listener; the report needs an explicit Iceberg-loading decision plus the correlated-generator requirement before W3 begins.

---

## Verification log

Checked 2026-07-18 against `1-data-ingestion-pipeline/` and `2-batch-analytics-layer/`.

### Seam 1 (Parquet → Iceberg hop): CONFIRMED — and worse than stated

- The S3 Sink writes plain Parquet: `io.confluent.connect.s3.format.parquet.ParquetFormat` in `1-data-ingestion-pipeline/task10-s3-sink-connector-config.json:10`, layout `topics/postgres.public.<table>/year=.../month=.../day=.../hour=...` (confirmed by `task10-validate-s3-archival.sh:126`). Only two "iceberg" hits in the entire ingestion layer, both **comments** in `task9-validate-cdc.sh:248,250`.
- The batch layer contains **no loader**: exhaustive search in `2-batch-analytics-layer/` found zero references to the ingestion output paths, no `MERGE INTO`/`LOAD DATA`, and the only `spark.read.parquet` calls read back test data the same job just wrote (`task5-iceberg-setup-job.yaml:231-235`, `task3-spark-s3-iceberg-test.yaml:203-207`). No Iceberg→Snowflake job either — `task4-snowflake-test-job.yaml:177-182` only writes a 3-row synthetic `CONNECTIVITY_TEST` table.
- **New finding — the batch tables don't even model the CDC data**: `task6-ecommerce-tables-job.yaml:221-432` creates `user_events`, `transactions`, `products`, `user_sessions` (behavioral-style schemas) — **not** the `users`/`products`/`orders`/`order_items` mirrors with `__op`/`__ts_ms`/`__source_lsn` CDC fields that its own spec's design.md specifies. They contain only hardcoded sample rows (`task6-ecommerce-tables-job.yaml:510-511,544-545,577-578`). So even the "done" Tasks 5–6 do not match the spec's data model; the batch layer currently models the *speed* layer's events, on the batch cluster, with no source.
- Bucket mismatch confirmed: batch defaults to `data-s3-bucket` (`task3-setup-s3-access.sh:21`), ingestion example decodes to `publicly-exposed-bucket-123123123` (`04-secrets.yaml.example:32`). Both read from secrets so they *can* be aligned, but the committed examples disagree.
- Iceberg catalog: HadoopCatalog, warehouse `s3a://<bucket>/iceberg-warehouse/` set at runtime (`task5-iceberg-setup-job.yaml:209`); warehouse commented out in the configmap (`task5-iceberg-catalog-config.yaml:17`).

### Seam 2 (uncoordinated streams): CONFIRMED

- `data-generator.py` is psycopg2-only (`:8`); no Kafka producer, no behavioral events anywhere in the ingestion layer (grep for `PAGE_VIEW|PURCHASE|KafkaProducer|user_events` → zero hits).
- Worse: even the OLTP data lacks real referential correlation — `orders.user_id` is a positional `generate_series` value (`data-generator.py:129`) and `order_items.product_id` is `uuid + 1000` (`:138`). The generator cannot currently produce coherent joinable data even within PostgreSQL itself, let alone correlated event/CDC pairs.

### Seam 3 (exactly-once / DLQ on source): CONFIRMED

- `task9-debezium-connector-config.json:45-52` sets `errors.tolerance: all`, `errors.deadletterqueue.topic.name: connect-dlq`, retry timeouts — on a **source** connector, where Connect DLQ delivery has no effect. Same pattern in all four `connectors/*-debezium-connector.json`.
- **New finding — delete semantics erased**: the SMT chain uses `delete.handling.mode: rewrite` (`task9:26-30`) and the per-table connectors add `ReplaceField$Value` dropping `__deleted`, so deletes become indistinguishable from upserts downstream — directly contradicting the validation script's own comment that DELETE is "critical for Iceberg" (`task9-validate-cdc.sh:248`).
- Schema Registry compatibility is `BACKWARD` (`task6-schema-registry.yaml:26`), as the review stated; v2's FULL-compat amendment stands.

### Secondary claims spot-checked

- `tasks.max: "24"` confirmed (`task10-s3-sink-connector-config.json:5`) on the monolithic sink. Additionally, the four per-table sinks in `connectors/` use `partition.duration.ms: "1000"` with a `path.format` down to `'second'=ss` and `rotate.interval.ms: "1000"` — a file per second per partition per task, a severe small-file pathology if those variants are ever deployed.
- No application source exists in the batch layer: all PySpark logic is embedded in ConfigMaps inside SparkApplication YAMLs; jars are baked into a local image via `Dockerfile` (`imagePullPolicy: Never`).

### Impact on the v2 report

1. W3 must include a **generator rewrite**: real FK-correlated OLTP data plus causally-linked behavioral events (shared order IDs/amounts between `PURCHASE` events and `orders` rows).
2. The Iceberg decision is now starker: since the batch tables don't model CDC data anyway, **replacing the S3 Sink with an Iceberg sink connector** (or adding a loader job AND redefining the task6 tables as CDC mirrors per the spec design) are both on the table — the "keep task5/6 as-is" assumption in the v2 report is wrong.
3. Add to the fix list: remove dead DLQ config from the Debezium connector, fix the delete-erasing SMT chain (keep `__deleted` or use `delete.handling.mode: none` with tombstones handled downstream), and never deploy the per-second-rotation sink variants.
