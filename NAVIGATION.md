# DataPipe — Project Navigation Guide

**Last updated**: 2026-07-18

New here? Read this first. It tells you which documents govern, which are historical, and where things live.

---

## 1. What this project is, in one paragraph

DataPipe is a local, Kubernetes-based Lambda-architecture data platform: PostgreSQL changes stream via Debezium CDC through Kafka into an Iceberg lakehouse on S3 (bronze/silver), onward to Snowflake marts via dbt (gold/batch), with a Spark Streaming → ClickHouse real-time path, all orchestrated by Airflow and observed by Prometheus/Grafana. It runs on `kind` clusters, Linux-first, within a 26Gi RAM budget. **The project is currently in a cohesiveness remediation program**: the ingestion pipeline works, but the layers were built independently and don't yet connect end-to-end. Fixing that is the active work.

## 2. Document authority (read in this order)

When documents disagree, the higher one wins:

| # | Document | Role | Status |
|---|---|---|---|
| 1 | **`datapipe-data-model.md`** | Canonical schemas, keys, types, naming for every layer. Any table/spec conflicting with it is broken. | ✅ CURRENT — governs data |
| 2 | **`datapipe-remediation-plan.md`** | The active program: decisions, resource budget, workstreams R0–R7 with exit criteria. **§11 (addendum) supersedes §§1–10** — the earlier v2 framing is kept for context only. | ✅ CURRENT — governs work |
| 3 | **`datapipe-v2-architecture-review.md`** | The verified findings that motivated remediation, including the implementation evidence log. Background for *why* the plan says what it says. | ✅ CURRENT — reference |
| 4 | **`.kiro/specs/*`** | The four original layer specs. Contain known contradictions (wrong data models, single-cluster assumptions, unsized budgets). See `.kiro/specs/README.md`. | ⚠️ SUPERSEDED — historical |
| 5 | **`README.md`, `CLAUDE.md`, `kiro.md`** | v1-era descriptions of the ingestion pipeline. Accurate about what physically exists in `1-data-ingestion-pipeline/`, but their status/roadmap sections are stale. | ⚠️ STALE — describes v1 only |
| 6 | **`original_requirements.txt`** | The owner's original requirements. Still the north star the remediation plan traces against. | ✅ CURRENT — intent |

**The 15-minute orientation**: `original_requirements.txt` → this file → `datapipe-remediation-plan.md` §11 → `datapipe-data-model.md` → skim `datapipe-v2-architecture-review.md`.

## 3. Repository layout

| Path | What it is | State |
|---|---|---|
| `1-data-ingestion-pipeline/` | PostgreSQL → Debezium → Kafka → S3 Sink pipeline: all K8s manifests, connector configs, deploy script, validation scripts, data generator | ✅ Works standalone. Known defects queued in workstream R2 (delete-erasing SMT chain, dead DLQ config, per-second sink variants in `connectors/` — **do not deploy those**) |
| `2-batch-analytics-layer/` | Batch cluster: Spark Operator, Iceberg catalog setup, S3/Snowflake connectivity | 🔨 Infra works, but the task-6 tables model the wrong data (see review) — rebuilt in R3/R4 |
| `utils-dev/` | Python (uv-managed) S3 Parquet query tools + Excel export | ✅ Works against the *old* Parquet layout |
| `logs/` | Execution and validation logs from v1 runs | Historical |
| `.kiro/specs/` | Original per-layer specs | ⚠️ Superseded (see §2) |
| Root docs | The governing documents from §2 | — |

## 4. Where to go depending on what you want

- **"I want to run what's working today"** → `README.md` (Getting Started) + `1-data-ingestion-pipeline/deploy-data-ingestion-pipeline.sh`. You need Docker/kind/kubectl and AWS credentials in `04-secrets.yaml` (copy from `.example`). Know that the deployed S3 sink config is scheduled for replacement (R3) and the per-table connectors in `connectors/` are hazardous.
- **"I want to work on the remediation"** → `datapipe-remediation-plan.md` §11.3, pick the current R-workstream. Check §11.6 + `datapipe-data-model.md` before touching any schema. The R0 spikes (Iceberg connector, cross-cluster Kafka listeners) gate everything.
- **"I want to understand why a decision was made"** → `datapipe-remediation-plan.md` §11 first; if the reasoning isn't there, `datapipe-v2-architecture-review.md` (evidence) or §7 "rejected alternatives" in `datapipe-data-model.md`.
- **"I want the original vision"** → `original_requirements.txt`, then the (superseded) specs for flavor — with the plan open to check what changed.

## 5. Standing rules for contributors

1. **Schemas**: never add/rename a column or table without updating `datapipe-data-model.md` first. It is the contract.
2. **Specs**: do not pick up tasks from `.kiro/specs/` — use the R-workstreams.
3. **Secrets**: `04-secrets.yaml` (gitignored) must be created from the `.example`; AWS and Snowflake are *real* cloud services — nothing emulates them locally.
4. **Deploy scripts**: `deploy-data-ingestion-pipeline.sh` currently wires the per-table connectors from `connectors/`; treat connector changes as R2/R3 work, not drive-by edits.
5. **New documents**: status-mark them (CURRENT / SUPERSEDED / DRAFT) at the top, and add a row to §2 of this guide if they're meant to govern anything.
