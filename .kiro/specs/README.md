# ⚠️ Specs Status: SUPERSEDED (2026-07-18)

The four specs in this directory (`data-ingestion-pipeline`, `batch-analytics-layer`, `realtime-analytics-speed-layer`, `orchestration-monitoring`) are **historical reference only**. They predate the cohesiveness remediation program and contain known contradictions with the current plan — including wrong data models, a single-cluster orchestration assumption, event topics with no producer, and per-layer RAM budgets that exceed the system total.

**Do not implement tasks directly from these specs.** What governs now:

1. `datapipe-remediation-plan.md` (repo root) — the remediation program, workstreams R0–R7, and all current architectural decisions (its §11 addendum supersedes the v2 framing in §§1–10 of the same file).
2. `datapipe-data-model.md` (repo root) — canonical schemas, keys, types, and naming for every layer.
3. `datapipe-v2-architecture-review.md` (repo root) — the verified findings that motivated the remediation, with the implementation evidence log.

Each spec will be rewritten in place as its corresponding R-workstream begins. Until a spec carries a "CURRENT" marker here, treat unchecked task boxes in it as *invalid*, not merely incomplete.

| Spec | Status | Superseded by |
|---|---|---|
| data-ingestion-pipeline | SUPERSEDED | R2 (CDC correctness), §11.2 (Iceberg sink) |
| batch-analytics-layer | SUPERSEDED | R3/R4, `datapipe-data-model.md` §2 |
| realtime-analytics-speed-layer | SUPERSEDED | R5, `datapipe-data-model.md` §3 |
| orchestration-monitoring | SUPERSEDED | R7, report §5.4–§5.6 |
