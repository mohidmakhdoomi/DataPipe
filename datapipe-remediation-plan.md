# DataPipe v2 — End-to-End Cohesiveness Report

**Status**: Draft
**Date**: 2026-07-18
**Scope**: Definition of DataPipe v2 — a new version of the project that preserves the original requirements, reuses the v1 implementation where it is sound, and makes **end-to-end cohesiveness across all layers** the primary design goal.

---

## 1. Executive Summary

DataPipe v1 delivered a working ingestion pipeline (PostgreSQL → Debezium CDC → Kafka → S3/Parquet) and the infrastructure foundations of a batch analytics layer (Spark Operator, Iceberg tables, S3/Snowflake connectivity). However, the four layers of the Lambda Architecture were specified and built **independently**: they run on separate kind clusters with no shared networking, no unified orchestration, no cross-layer monitoring, and — most critically — **no single path that carries one record from source to serving**.

DataPipe v2 keeps the v1 requirements and components, but re-scopes the project around **one question: can a single business event flow, observably and correctly, through every layer of the system?** Every architectural decision in v2 is evaluated against that question.

### Key decisions for v2 (confirmed with project owner)

| Decision | Choice |
|---|---|
| Cluster topology | **Keep separate kind clusters per layer** (ingestion, batch, speed, orchestration) |
| Target platform | **Linux-first**, manifests kept OS-agnostic/portable |
| Gap commitments | **Validate 10,000 events/sec end-to-end**; deliver **exactly-once semantics and backward+forward schema compatibility** |
| Explicitly not committed | Backup/DR beyond what v1 already has (remains optional future work) |

---

## 2. Background: v1 State Assessment

### 2.1 What exists and works

| Layer | Status | Reusable in v2 |
|---|---|---|
| Ingestion (`1-data-ingestion-pipeline/`) | ✅ Complete, operational | Yes — as-is, minor amendments (§5.1) |
| Batch infra (`2-batch-analytics-layer/`) | 🔨 Cluster, Spark Operator, S3 + Snowflake connectivity, Iceberg catalog + 4 tables done | Yes — foundation kept; all processing logic (Tasks 7–16) still to be built |
| Speed layer | ⬜ Spec only | Spec reused with amendments (§5.3) |
| Orchestration/monitoring | ⬜ Spec only | Spec reused but **redesigned for multi-cluster** (§5.4) |
| `utils-dev/` query tools | ✅ Working | Yes, extended for cross-layer validation |

### 2.2 Cohesiveness gaps identified in v1

1. **No cross-cluster story.** The ingestion and batch clusters cannot see each other. The orchestration spec assumed a single cluster with direct Prometheus scraping of Kafka/ClickHouse — it was never reconciled with the actual multi-cluster layout.
2. **A conceptual break in the data model.** The speed-layer spec consumes behavioral event topics (`user_events`, `transactions`) that **nothing produces**. The ingestion pipeline emits CDC topics (`postgres.public.*`) from OLTP tables. The layers do not connect, even on paper.
3. **Unvalidated headline requirement.** 10,000 events/sec was specified in three specs and tested in none. Validated baseline: 1,000 events/sec.
4. **Semantic drift from requirements.** Requirements ask for exactly-once delivery and backward+forward schema compatibility; v1 implements at-least-once and BACKWARD-only.
5. **Budget overrun on paper.** Per-layer budgets total 6 + 12 + 9.5 + 8 = **35.5Gi against the 26Gi system cap** — the layers were sized independently without a global budget.
6. **Four independent task trackers.** Each spec has its own `tasks.md`; there is no end-to-end acceptance criterion anywhere.

---

## 3. v2 Vision and Goals

### 3.1 Vision statement

> One event, generated in PostgreSQL, is visible within seconds in ClickHouse real-time views, within minutes in S3/Iceberg, within the hour in Snowflake marts — with Airflow orchestrating, Prometheus observing, and the batch and speed views automatically reconciled.

### 3.2 Goals (in priority order)

- **G1 — End-to-end data path.** A documented, tested, continuously-monitored path from `orders` table INSERT to ClickHouse dashboard to Snowflake mart, with CDC lineage fields (`__op`, `__ts_ms`, `__source_lsn`) preserved at every hop.
- **G2 — Cross-cluster cohesiveness.** Defined networking, service discovery, secrets propagation, orchestration, and monitoring across the four kind clusters.
- **G3 — Validated throughput.** Demonstrate 10,000 events/sec sustained through the ingestion path and the speed path, with latency and lag budgets published.
- **G4 — Delivery semantics.** Exactly-once (or effectively-once, explicitly documented where) across Kafka produce/consume and sink writes; Schema Registry set to FULL (backward+forward) compatibility.
- **G5 — Single-command lifecycle.** One umbrella deployment brings up all four clusters in dependency order; one validation suite verifies the whole system.

### 3.3 Non-goals

- Production cloud deployment (project remains local-only).
- BI/reporting tool selection; dedicated observability product evaluation (Prometheus/Grafana remain the built-in choice per the orchestration spec).
- Backup/DR expansion (PITR, Velero) — carried as optional backlog, unchanged from v1.
- Multi-node production hardening of Kafka/ClickHouse beyond dev-parity.

---

## 4. Requirements Traceability

v2 preserves the original requirements (`original_requirements.txt`) with the following amendments:

| Original requirement | v2 disposition |
|---|---|
| All 11 technologies (PostgreSQL, Kafka, S3, Iceberg, Spark, dbt Core, Snowflake, ClickHouse, Airflow, Docker, Kubernetes) | **Kept.** Each has a defined role in the end-to-end path (§5). |
| Lambda Architecture | **Kept**, sharpened: batch and speed layers consume the *same source* and are *automatically reconciled* (§5.6). |
| 10,000 events/sec | **Kept**, now with a committed validation workstream (§7, W6). |
| Out-of-the-box over custom code | **Kept.** Custom code limited to: data/event generator, Spark batch + streaming jobs, dbt models, Airflow DAGs. |
| Docker Desktop on Windows | **Amended** → Linux-first, OS-agnostic manifests. No Windows-specific tooling; Docker Desktop noted as an untested-but-expected-to-work path. |
| kind + containerd | **Kept.** |
| 26Gi RAM / 10 CPU / 1TB | **Kept**, with a global re-budget across clusters (§6). |
| Airflow DAGs outside the image, hot-reloadable | **Kept** (git-sync sidecar, ≤2 min propagation). |
| External PVs for PostgreSQL/Kafka/ClickHouse | **Kept.** |
| Real S3 + Snowflake (no local emulation) | **Kept.** |
| Spark on Kubernetes | **Kept** (Spark Operator on both batch and speed clusters). |
| BI tool and observability tooling out of scope | **Partially amended.** External BI remains out of scope; the built-in Prometheus/Grafana/Alertmanager stack from the orchestration spec **is** in scope as pipeline-health infrastructure (not a product decision). |

New requirements introduced by v2:

- **R-N1 (Cross-cluster networking):** any layer SHALL reach the published endpoints of any other layer through a documented, reproducible mechanism.
- **R-N2 (Unified orchestration):** Airflow SHALL be able to submit and monitor workloads on all clusters from a single control plane.
- **R-N3 (Unified monitoring):** a single Grafana SHALL display health and throughput of all layers; alerts SHALL fire on end-to-end lag, not only per-component state.
- **R-N4 (Contract continuity):** schemas and lineage fields SHALL be consistent and versioned across all layers via the single Schema Registry.
- **R-N5 (End-to-end acceptance):** the project SHALL ship an automated end-to-end validation that proves G1–G4.

---

## 5. v2 Architecture

### 5.0 Topology overview

Four kind clusters on one Docker network, one concern each:

```txt
┌────────────────────┐   ┌────────────────────┐
│  ingestion cluster │   │   speed cluster    │
│  PostgreSQL        │   │  Spark Streaming   │◄── Kafka topics
│  Kafka (KRaft ×3)  │──►│  ClickHouse        │    (NodePort)
│  Schema Registry   │   └─────────┬──────────┘
│  Kafka Connect     │             │
└─────────┬──────────┘             │ reconcile
          │ S3/Parquet             ▼
          ▼                ┌────────────────────┐
┌────────────────────┐     │  batch cluster     │
│  AWS S3 ──Iceberg──┼────►│  Spark Operator    │
└────────────────────┘     │  → Snowflake → dbt │
                           └─────────▲──────────┘
                                     │ submits/monitors
                           ┌─────────┴──────────┐
                           │ orchestration      │
                           │ Airflow (git-sync) │
                           │ Prometheus/Grafana │
                           └────────────────────┘
```

### 5.1 Ingestion layer (reuse, minor amendments)

Reuse `1-data-ingestion-pipeline/` essentially as-is. Amendments:

- **Schema Registry compatibility: `BACKWARD` → `FULL`** (closes the backward+forward requirement).
- **Exactly-once path**: enable Kafka transactional/idempotent producer settings on Debezium (`producer.override.enable.idempotence=true` already default in modern Debezium; verify), set consumer `isolation.level=read_committed` on the S3 Sink, and document where exactly-once is *not* achievable (S3 object writes are effectively-once via partition + offset naming; stated plainly in docs).
- **Expose Kafka + Schema Registry for cross-cluster access**: NodePort/published listener with an advertised address resolvable from sibling clusters (§5.5).
- **Publish schemas as the contract**: the Avro schemas in Schema Registry become the canonical contract that the speed layer's event producer must also register against (§5.3).
- **Throughput hardening** per W6: partition count review (6 → 12 for hot topics), S3 Sink `tasks.max` alignment, Connect heap tuning.

### 5.2 Batch layer (continue from Task 7)

Keep everything built (cluster, Spark Operator, Iceberg catalog, 4 e-commerce tables with CDC metadata). Remaining work per the existing spec, unchanged in substance:

- Spark batch jobs (customer/product/order analytics) reading `iceberg.ecommerce.*` (Tasks 7–8).
- Snowflake Raw → Staging → Marts via dbt Core (Tasks 9–14).
- **Amendment**: Spark jobs must carry CDC lineage fields into Snowflake Raw (`__op`, `__ts_ms`, `__source_lsn`) so reconciliation and debugging can trace any row back to the WAL.
- **Amendment**: Snowflake loads are triggered **by Airflow**, not by manual scripts (§5.4).

### 5.3 Speed layer (spec reused, one structural fix)

The v1 speed-layer spec assumed `user_events`/`transactions` topics that nothing produces. v2 resolves this by **making the ingestion layer the event source**:

- **Amendment — event generation**: extend `data-generator.py` (or add a sibling generator) to emit the 9 behavioral event types (PAGE_VIEW … PURCHASE, per the spec's mix) to dedicated Kafka topics on the ingestion cluster, as Avro, registered in Schema Registry. This keeps "Kafka as the single streaming backbone" and gives the speed layer a real, schema-governed input.
- CDC topics (`postgres.public.orders`) remain the transactional truth; behavioral topics feed sessionization/funnels. Reconciliation joins on shared IDs.
- Everything else per spec: 2s micro-batches, `flatMapGroupsWithState` 30-min sessions, tier enrichment via PostgreSQL lookup w/ 15-min cache, ClickHouse `ReplicatedMergeTree` + 3 materialized views, DLQ topics.

### 5.4 Orchestration & monitoring (redesigned for multi-cluster)

This layer changes the most. The v1 spec assumed one cluster; v2 makes it the **control plane for four**:

- **Airflow** (KubernetesExecutor, git-sync DAGs — unchanged mechanism) gains a `kubeconfig` with one context per cluster. All `KubernetesPodOperator`/`SparkKubernetesOperator` tasks take an explicit `cluster_context`. Connections (PostgreSQL, Kafka, ClickHouse, Snowflake, S3) defined once, centrally.
- **DAG set** (all git-synced):
  - `daily_batch_processing` — quality check → Spark batch (batch cluster) → Snowflake load → dbt run → reconciliation → report.
  - `realtime_monitoring` (5 min) — end-to-end lag probe, freshness, DLQ depth, alert evaluation.
  - `e2e_validation` (on demand) — the G5 acceptance suite.
- **Monitoring**: one Prometheus on the orchestration cluster scrapes remote clusters via their published metrics endpoints (NodePort/exporter addresses registered in a static, version-controlled targets file — deliberately simple over federation). Grafana dashboards: Pipeline Overview (per-hop rates, end-to-end lag), Component Health, Lambda Reconciliation. Alertmanager per v1 spec, with the key alert changed from component-state to **end-to-end lag > threshold**.
- **Out of the v1 spec, dropped for v2**: Fluentd→Elasticsearch→Kibana log aggregation (~1.5Gi and significant complexity for local dev; `kubectl logs` + container runtime logs suffice). This is an explicit descope, recorded here.

### 5.5 Cross-cluster networking (the core cohesiveness mechanism)

Deliberately boring, no service mesh:

- All four kind clusters join a **single shared Docker network** (`kind` default network extended, or a dedicated `datapipe` Docker network passed to `kind create cluster --network`).
- Inter-cluster service access via **NodePort + shared-network address**, with published endpoints recorded in one version-controlled `clusters/endpoints.yaml` (source of truth consumed by deployment scripts, Airflow connections, and Prometheus targets).
- TLS remains as per v1 per-cluster posture (PLAINTEXT inside kind, TLS to S3/Snowflake); cross-cluster traffic stays inside the Docker network. Documented as a local-dev tradeoff.

### 5.6 Lambda reconciliation (made real)

v1 specified reconciliation (ClickHouse vs Snowflake, 5% tolerance) but left it unimplemented. v2 promotes it to the **proof that the Lambda architecture works**: an Airflow task compares `daily_business_metrics` (Snowflake mart) against ClickHouse aggregates per date, writes a reconciliation report, alerts at >5% (warning) / >10% (critical), and publishes `lambda_reconciliation_discrepancy` to Prometheus.

---

## 6. Global Resource Budget (26Gi)

Keeping separate clusters requires an explicit global budget; v1's per-layer numbers (35.5Gi) do not fit. v2 re-budget, using v1 *actuals* where known:

| Cluster | v1 budget | v1 actual | v2 budget | Notes |
|---|---|---|---|---|
| Ingestion | 6Gi | 3.8Gi | **5Gi** | Actuals prove headroom; keep 1Gi margin |
| Batch | 12Gi | — (untested) | **9Gi** | Driver 2Gi + 2×3Gi executors + dbt 1Gi |
| Speed | 9.5Gi | — (unbuilt) | **7Gi** | ClickHouse 4Gi + driver 1Gi + executor 1.5Gi + margin |
| Orchestration | 8Gi | — (unbuilt) | **4Gi** | Airflow 2Gi + Prometheus 1.5Gi + Grafana 0.5Gi (ELK dropped) |
| **Total** | 35.5Gi | | **25Gi** | 1Gi spare under the 26Gi cap |

Budgets become **enforced ResourceQuotas** per cluster, replacing v1's advisory numbers. The dynamic Spark pool idea from the speed-layer spec is dropped (cross-cluster preemption is not implementable simply); static budgets + AQE are the v2 answer.

---

## 7. Workstreams and Roadmap

Sequenced so that cohesiveness infrastructure lands **before** new layer features.

- **W1 — Cohesiveness foundation** (prerequisite for everything): shared Docker network, `endpoints.yaml`, cross-cluster kubeconfig, umbrella deploy/teardown scripts, global ResourceQuotas. *Exit: from the orchestration cluster, `curl` succeeds against Kafka, ClickHouse, and Spark Operator APIs on the other clusters.*
- **W2 — Orchestration control plane**: Airflow + git-sync + connections + `realtime_monitoring` DAG skeleton; Prometheus + Grafana + static cross-cluster targets; end-to-end-lag alert. *Exit: one Grafana dashboard shows live metrics from all four clusters.*
- **W3 — Event source fix + speed layer**: behavioral event generator → Avro topics on ingestion cluster; ClickHouse; Spark Streaming app; DLQs. *Exit: events visible in ClickHouse materialized views within seconds of generation.*
- **W4 — Batch completion**: Spark batch jobs, Snowflake schemas, dbt project (staging → marts), all Airflow-triggered. *Exit: `daily_batch_processing` DAG green end-to-end.*
- **W5 — Reconciliation**: comparison job, reports, Prometheus metric, alerts. *Exit: reconciliation report produced daily; injected discrepancy triggers alert.*
- **W6 — Throughput & semantics validation**: load generator at 10k events/sec sustained (ingestion path and speed path separately, then combined); publish latency/lag budgets; verify FULL compatibility rejects breaking schemas; document exactly-once boundaries. *Exit: validation report committed to repo.*
- **W7 — End-to-end acceptance**: `e2e_validation` DAG — inject known event/orders, assert presence and correctness in ClickHouse, S3/Iceberg, and Snowflake, assert reconciliation passes, assert lineage fields intact. *Exit: one command proves G1–G4.*

### Suggested milestones

- **M1 (W1–W2)**: "One control plane" — all clusters observable and orchestratable.
- **M2 (W3)**: "Real-time works" — events flow to ClickHouse.
- **M3 (W4–W5)**: "Lambda works" — batch path complete, reconciliation live.
- **M4 (W6–W7)**: "Proven" — 10k validated, semantics documented, e2e suite green.

---

## 8. Risks and Open Questions

| Risk / question | Mitigation / disposition |
|---|---|
| 26Gi budget may not hold when all layers run simultaneously | v2 budget uses v1 actuals; ResourceQuotas enforce; W6 includes a combined-load soak test; fallback is reducing ClickHouse allocation |
| Cross-cluster NodePort networking on kind is brittle across Docker restarts | `endpoints.yaml` is regenerated by the umbrella deploy script, not hand-maintained |
| Behavioral-event generator adds custom code | Bounded scope (one Python producer, schemas registered in SR); no alternative exists since nothing else produces these events |
| ClickHouse on 4Gi may not meet sub-second queries at 50 concurrent users | Validate in W6; the spec's 50-concurrent-user target is marked stretch for local dev |
| Airflow worker pods on the small orchestration cluster | KubernetesExecutor workers are short-lived and budgeted; batch Spark work runs on the batch cluster, not here |
| Exactly-once across S3 writes is not literally achievable | G4 explicitly scoped: idempotent/transactional in Kafka; effectively-once at sinks via deterministic object naming; boundaries documented |
| Schema Registry as single point of contract for all clusters | Accepted; it lives on the ingestion cluster and is published via `endpoints.yaml` like any other endpoint |

---

## 9. What v2 Explicitly Does NOT Change

- The ingestion pipeline's component choices (Debezium, KRaft Kafka, Confluent S3 Sink, Parquet/Snappy, hourly partitioning).
- The batch layer's built infrastructure and spec's data models (tiers, KPIs, mart definitions).
- The speed layer's ClickHouse schema design and sessionization approach.
- Local-only scope; real S3/Snowflake; out-of-the-box-first philosophy.
- MIT license, manifest-first (no Helm requirement), bash/Python tooling style.

---

## 10. Appendix: Per-Layer Disposition Summary

| Layer | Spec changes needed | Code/infra changes |
|---|---|---|
| Ingestion | Small amendment: FULL compat, exactly-once boundaries, endpoint publication | SR config flag, consumer `isolation.level`, advertised listeners, partition review |
| Batch | Small amendment: Airflow-triggered loads, lineage fields | Tasks 7–16 as specified |
| Speed | One structural fix: real event source; budget cut 9.5→7Gi | Full build per amended spec |
| Orchestration | Significant redesign: multi-cluster Airflow/Prometheus; ELK dropped; budget 8→4Gi | Full build per amended spec |
| Cross-cutting | New: endpoints.yaml, global budget, e2e acceptance | W1, W7 |

---

## 11. Addendum (2026-07-18): Reframing — from "v2" to cohesive remediation

**This addendum supersedes the framing above wherever they conflict.**

Verification of this report's claims against the actual implementation (full evidence log: `datapipe-v2-architecture-review.md`, "Verification log" section) invalidated several load-bearing assumptions. The project is therefore reframed: **not a new version of DataPipe, but a remediation program** that fixes the seams in the current implementation first, and completes the missing layers on top of the corrected foundation.

### 11.1 Verified findings that change the plan

1. **No Parquet→Iceberg loader exists** anywhere in the batch layer (confirmed: zero reads of the sink's `topics/.../year=/month=/day=/hour=` output).
2. **The "done" batch tables (tasks 5–6) model the wrong data.** `task6` creates `user_events`, `transactions`, `user_sessions` — behavioral schemas with no source — not the `users`/`products`/`orders`/`order_items` CDC mirrors with `__op`/`__ts_ms`/`__source_lsn` that its own spec's design.md specifies. §2.1's "batch infra reusable" assessment was wrong.
3. **The data generator produces incoherent data even within PostgreSQL** (`orders.user_id` = positional number, `order_items.product_id` = `uuid + 1000`) and emits no behavioral events at all. "Extend the generator" (§5.3) understates it: the generator must be **rewritten**.
4. **The CDC stream erases deletes.** The SMT chain (`delete.handling.mode: rewrite` + `ReplaceField` dropping `__deleted`) makes deletes indistinguishable from upserts — fatal for any Iceberg replica of the source tables.
5. **Dead config confirmed**: DLQ/`errors.tolerance` on the Debezium *source* connector (no effect in Kafka Connect); `tasks.max=24` on a 2Gi worker; per-table sink variants in `connectors/` rotating **every second** (small-file pathology — never deploy these).
6. Bucket names disagree between layers (`data-s3-bucket` vs `publicly-exposed-bucket-123123123` in the committed examples).

### 11.2 Decision: Iceberg sink in append mode — the medallion bronze layer

With the task 5–6 tables needing redefinition regardless, the two options from the architecture review were re-evaluated against the **medallion architecture** (bronze/silver/gold) the project is now committed to:

- **Option A — Iceberg sink connector**: replace the Confluent S3 Sink with the Apache Iceberg Kafka Connect connector. The archive *becomes* an Iceberg table — one hop, no loader, ACID + time travel at rest, deletes propagatable. Keeps the Avro/Schema Registry contract. Removes the Parquet-format/hourly-partition config surface (and the pathological per-second variants) entirely.
- **Option B — keep S3 Sink + Spark loader job**: bronze as plain Parquet dumps — no ACID, no schema evolution, no time travel, small-file-prone, barely queryable; a permanent second hop, a second copy of the data, and an Airflow-dependent lag before anything is usable.

**Decision: Option A, run in append mode, with an explicit silver merge step.** Medallion is about what happens *after* landing; Option A in append mode yields a proper bronze (immutable, replayable CDC event log with ACID, time travel, and schema evolution), whereas Option B's raw Parquet is bronze in name only. Layering:

```txt
BRONZE  iceberg.ecommerce_raw.*     Iceberg sink (append mode) — every CDC event,
                                    immutable, __op/__ts_ms/__source_lsn intact,
                                    partitioned by hours(__source_ts_ms) transform
SILVER  iceberg.ecommerce.*         Spark MERGE INTO — current-state mirrors of
                                    users/products/orders/order_items; deletes applied,
                                    deduped, validated; first real Spark batch job
GOLD    Snowflake marts.*           dbt staging → marts (as already spec'd)
SPEED   ClickHouse                  outside medallion; reconciled against gold
```

Design rules for this decision:

1. **The silver merge is not optional.** In append mode bronze is an event log, not a replica; current state exists only after applying ops. Do **not** use the connector's upsert mode — it collapses bronze and silver into one table, loses the event log, and re-couples the layers.
2. **Small files move, not disappear.** Connect flushes create small Iceberg data files; the answer is Iceberg-native `rewrite_data_files` compaction as a scheduled Airflow task — not Parquet-directory management.
3. **Maturity caveat.** The Iceberg Kafka Connect connector is much younger than the Confluent S3 Sink. R0 must spike it against the Avro/Schema Registry input (including schema evolution). Fallback if it fails: Option B, but with the loader's Iceberg output treated as bronze (landing within minutes), never the raw Parquet.
4. The R2 delete-semantics fix (preserve `__op`/`__deleted` through the SMT chain) is a hard prerequisite — the silver merge is where deletes are finally applied.

### 11.3 Revised workstreams (remediation-first)

Replaces §7's W1–W7 ordering. Nothing new is built until the seams are fixed.

| # | Workstream | Content | Exit criterion |
|---|---|---|---|
| **R0** | Decisions & spikes | Spike Iceberg sink connector vs Avro/Schema Registry input incl. schema evolution (§11.2 rule 3); spike cross-cluster Kafka advertised listeners (host-port variant per review #7) | Connector spike report recorded; a consumer on a sibling kind cluster reads from ingestion Kafka |
| **R1** | Generator rewrite | Per `datapipe-data-model.md`: add `tier`/`is_active` to `users` DDL + sample data (tiers per 60/25/12/3); real FK-correlated OLTP data; canonical `UserEvent` Avro schema registered in Schema Registry; correlated PURCHASE ↔ `orders`/`order_items` pairs per the §3.2 field contract; produce to `events.user_events` | Reconciliation-relevant joins resolve; event and CDC streams agree on a known workload |
| **R2** | CDC stream correctness | Fix SMT chain (preserve delete semantics — `delete.handling.mode: none`, keep `__deleted`); remove dead DLQ config from source connector; align sink `tasks.max` to worker budget; delete or quarantine the per-second sink variants; Schema Registry → FULL; `decimal.handling.mode=precise`; verify the `users` DDL change (tier/is_active) evolves cleanly through Schema Registry | A DELETE in PostgreSQL is represented correctly end-to-end; schema-compat level verified; money lands as `decimal(10,2)` |
| **R3** | Medallion bronze + silver | Deploy Iceberg sink (append mode) writing **six** bronze tables — `ecommerce_raw.{users,products,orders,order_items}` partitioned by `hours(__source_ts_ms)` plus `ecommerce_raw.user_events` partitioned by `hours(event_time)`; rebuild silver `ecommerce.*` current-state mirrors via Spark `MERGE INTO` (deletes applied, deduped) plus `ecommerce.user_sessions` (batch sessionization on `session_id`); align bucket naming; schedule `rewrite_data_files` compaction | A row inserted, updated, **and deleted** in PostgreSQL is reflected correctly in the silver tables with lineage intact, without manual steps |
| **R4** | Batch completion | Spark batch jobs reading the Iceberg CDC mirrors; Snowflake Raw mirrors **silver** (not bronze); Staging/Marts via dbt with `customer_tier` projecting `users.tier`; Airflow-triggered | `daily_batch_processing` DAG green |
| **R5** | Speed layer | ClickHouse per `datapipe-data-model.md` §3.5: integer IDs (no UUID), plain `MergeTree` (no Keeper), no `transactions_realtime`, `purchase_reconciliation_mv` added; Spark Streaming consuming `events.user_events`; tier enrichment from the `postgres.public.users` CDC stream — **no cross-cluster PostgreSQL reads** | Events visible in ClickHouse MVs within seconds |
| **R6** | Reconciliation | ClickHouse vs Snowflake per the keys in `datapipe-data-model.md` §4 (integer IDs throughout — spec's UUID→STRING notes are void); 5% warn / 10% crit; event-time semantics fixed per review | Injected discrepancy fires the alert |
| **R7** | Control plane & proof | Airflow + git-sync, Prometheus/Grafana cross-cluster targets, end-to-end-lag alert; 10k events/sec validation; `e2e_validation` suite | One command proves the whole path; validation report committed |

### 11.4 What this changes in the original report

- **§2.1**: batch layer infra is kept (cluster, Spark Operator, connectivity) but tasks 5–6 outputs are **rebuilt**, not reused.
- **§5.1**: ingestion amendments now *include* the R2 fixes (SMT chain, dead DLQ, sink task sizing) and the sink replacement itself (Confluent S3 Sink → Iceberg sink, §11.2) — the layer is no longer "as-is".
- **§5.3**: "extend `data-generator.py`" → "rewrite the generator" (R1).
- **§7**: W1–W7 superseded by R0–R7 (§11.3); milestones M1–M4 map onto R0–R1 (foundation), R2–R3 (seams fixed), R4–R6 (layers completed), R7 (proven).
- **Data model**: `datapipe-data-model.md` (§11.6) is the canonical schema reference for all layers; the four `.kiro/specs/` are historical (see `.kiro/specs/README.md`).
- **Unchanged**: topology (separate clusters), Linux-first, the 26Gi re-budget (§6), requirements traceability (§4), and the §5.5/§5.6 mechanisms — subject to the R0 spike.

### 11.5 Operating principle

From here on, every change is evaluated by one test: **does it make the end-to-end path — PostgreSQL row or behavioral event → stream → Iceberg → Snowflake, and → ClickHouse, reconciled and observable — work, or work more verifiably?** Work that doesn't move that needle (new features, new layers, cosmetic refactors) is out of scope until R7 exits green.

### 11.6 Canonical data model

The cross-layer data model is codified in **`datapipe-data-model.md`**, which governs every entity, key, type, and naming convention in the project. Key decisions (rationale and rejected alternatives are in that document):

- **Integer IDs end-to-end** (ClickHouse drops UUID types); UUIDs only for non-joinable `event_id`/`session_id`.
- **`users` gains `tier` + `is_active`** — tier's single authoritative home is the OLTP schema; the speed layer enriches from the `postgres.public.users` CDC stream instead of cross-cluster PostgreSQL reads (resolves review #8).
- **One canonical `UserEvent` Avro schema**, one topic (`events.user_events`), with a per-event-type field contract — `PURCHASE` must carry `order_id` + `amount` equal to the corresponding `orders` row (the reconciliation linchpin).
- **Behavioral events land in bronze too** — `ecommerce_raw.user_events` via the same Iceberg sink; silver adds `ecommerce.user_sessions`. Bronze is six tables, not four.
- **Money as `decimal(10,2)` everywhere** (`decimal.handling.mode=precise`); `transactions_realtime` retired; Snowflake Raw mirrors silver, not bronze.

Where any spec or existing table conflicts with `datapipe-data-model.md`, the data model document wins and the layer is considered broken.
