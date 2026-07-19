---
name: Data Engineering Principles
description: Use when building data pipelines, warehouses, or ETL/ELT — Kimball modeling, SCD, partitioning, data quality, pipeline patterns
globs: ["**/*.sql", "**/migrations/**", "**/schema/**", "**/etl/**", "**/pipelines/**", "**/warehouse/**", "**/analytics/**", "**/*.py"]
---

# Data Engineering Principles & Laws

Sources: "Designing Data-Intensive Applications" (Kleppmann), "Fundamentals of Data Engineering" (Reis/Housley), "The Data Warehouse Toolkit" (Kimball/Ross)

## DDIA Core Principles (Kleppmann)

### Three Pillars
1. **Reliability**: correct results even when faults occur
2. **Scalability**: handles growth gracefully
3. **Maintainability**: operability + simplicity + evolvability

### Data Models & Query Languages
- Relational (SQL): strong schema, joins, ACID — best for structured transactional data
- Document (JSON/BSON): flexible schema, nested — best for self-contained entities
- Graph: relationships are first-class — best for highly connected data
- Choose based on access patterns, not hype

### Storage & Retrieval
- **B-tree indexes**: general purpose, good for random reads (PostgreSQL default)
- **LSM-trees**: optimized for write-heavy (RocksDB, Cassandra)
- **Column-oriented**: optimized for analytics/aggregation (ClickHouse, Parquet)
- **HNSW index**: approximate nearest neighbor for vector search (pgvector)

### Replication & Partitioning
- **Single-leader**: one writer, many readers (PostgreSQL streaming replication)
- **Multi-leader**: multiple writers (conflict resolution needed)
- **Leaderless**: quorum reads/writes (Cassandra, DynamoDB)
- **Partitioning**: range (time-series), hash (even distribution), composite

## Data Modeling Methodologies

### Kimball (Bottom-Up): fact tables (events) + dimension tables (context) → star schema. Quick wins
### Inmon (Top-Down): 3NF enterprise warehouse → derived data marts. Single source of truth
### Data Vault 2.0: hubs (keys) + links (relationships) + satellites (attributes with full history). Auditable
### One Big Table (OBT): denormalize everything into wide table. Modern columnar engines handle it well

## Pipeline Principles

### Idempotent Pipelines (CRITICAL)
"Running twice with same input produces same output."
- UPSERT (INSERT ON CONFLICT) instead of INSERT
- Partition-level overwrite instead of append
- Timestamp-based processing windows

### ETL vs ELT
- **ETL**: transform before loading. When compute is expensive at destination
- **ELT**: load raw, transform in warehouse. Modern preference (storage is cheap)

### Backpressure: buffer (queue), drop (policy), signal (tell producer to slow down)

### Schema Evolution
- Schema-on-write (RDBMS): catches errors early, harder to evolve
- Schema-on-read (JSON/lake): flexible ingestion, errors at query time
- Hybrid: bronze (raw) → silver (cleaned) → gold (business-ready)

## Data Quality Framework

### Six Dimensions
1. **Completeness**: no missing critical fields
2. **Accuracy**: values reflect reality
3. **Consistency**: same data, same format everywhere
4. **Timeliness**: current enough for use case
5. **Uniqueness**: no unwanted duplicates
6. **Validity**: conforms to expected schema/range

### Pipeline SLOs
- Freshness: data available within X minutes of event
- Completeness: >99% of expected records present
- Accuracy: <0.1% quality errors
- Monitor and alert on violations

## Slowly Changing Dimensions (SCD)
- **Type 1**: overwrite (no history) — typo corrections
- **Type 2**: add new row with valid_from/valid_to (full history) — most common
- **Type 3**: add previous_value column (limited history) — only most recent change

## Data Mesh (Zhamak Dehghani)
1. **Domain ownership**: each team owns their data as a product
2. **Data as a product**: SLOs, documentation, discoverability
3. **Self-serve infrastructure**: platform provides tools
4. **Federated governance**: global standards, local autonomy

## Materialized Views
- Full refresh: simple, locks table. `REFRESH MATERIALIZED VIEW`
- Concurrent: no lock, needs unique index. `REFRESH ... CONCURRENTLY`
- pg_cron: automate refresh interval (every 5 min for dashboards)
- When to materialize: query >1s, runs >10x/day, aggregation of large tables

## Time-Series Data
- Range partition by time (monthly/weekly for high-volume)
- Partition pruning: time filter automatically skips irrelevant partitions
- Retention: define per category, automate via pg_cron
- Aggregate before delete: daily summaries survive after raw data purge

## Data Pipeline Architecture Patterns
- **Lambda**: batch layer + speed layer + serving layer (complex, two codepaths)
- **Kappa**: stream-only processing, replay from log (simpler, modern)
- **Medallion (Databricks)**: bronze → silver → gold (incremental quality)
- **Event Sourcing**: store events, derive state. Full audit trail, replay capability

## 9 Principles of Good Data Architecture (Reis & Housley)

Source: "Fundamentals of Data Engineering" (O'Reilly, 2022)

1. **Choose Common Components Wisely**: standardize on shared tools (PostgreSQL, S3, Kafka/NATS) across teams to reduce operational burden
2. **Plan for Failure**: every component will fail. Design for graceful degradation, automatic recovery, data loss prevention
3. **Architect for Scalability**: design to handle 10x current load. Horizontal scaling > vertical scaling
4. **Architecture Is Leadership**: architects must influence, communicate, and get buy-in — not just draw diagrams
5. **Always Be Architecting**: architecture is never "done." Continuously evaluate and evolve as requirements change
6. **Build Loosely Coupled Systems**: services communicate via well-defined interfaces (APIs, events). Change one without breaking others
7. **Make Reversible Decisions**: prefer decisions that can be changed later. Avoid one-way doors when possible
8. **Prioritize Security**: security is not an afterthought. Encrypt, authenticate, authorize at every layer
9. **Embrace FinOps**: understand and optimize cloud costs. Monitor spend per pipeline, per query, per team

## Data Engineering Lifecycle Undercurrents

Six foundations that support ALL data engineering work:
1. **Security**: access control, encryption, compliance, PII handling
2. **Data Management**: governance, lineage, cataloging, quality, metadata
3. **DataOps**: automation, monitoring, observability, incident response for data pipelines
4. **Data Architecture**: the blueprint — how data flows, is stored, transformed, served
5. **Orchestration**: scheduling, dependency management, retry logic (Temporal, Airflow, pg-boss)
6. **Software Engineering**: version control, testing, CI/CD, code review — applies to data pipelines too
