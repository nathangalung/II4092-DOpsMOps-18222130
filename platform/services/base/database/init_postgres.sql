-- ============================================================================
-- Pipeline OLTP Schema (PostgreSQL)
-- ============================================================================
-- TEMPLATE: Domain-agnostic pipeline metadata tables.
-- All use-cases share this schema for pipeline run tracking, data quality
-- results, and prediction state management.
--
-- Use-cases can extend with domain-specific tables in their own
-- database/init_postgres.sql (e.g., domain-specific prediction fields).
--
-- Synced to ClickHouse via Debezium CDC for analytical queries.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pipeline;

-- ============================================================================
-- Pipeline Run Metadata
-- ============================================================================
-- Tracks every pipeline execution (ingestion, validation, feature, training).
-- Provides auditability and SLA monitoring.
CREATE TABLE IF NOT EXISTS pipeline.runs (
    id SERIAL PRIMARY KEY,
    run_type VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'running',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    records_processed BIGINT DEFAULT 0,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_runs_type_status ON pipeline.runs(run_type, status);
CREATE INDEX IF NOT EXISTS idx_runs_started ON pipeline.runs(started_at DESC);

-- ============================================================================
-- Data Quality Check Results
-- ============================================================================
-- Stores results from Great Expectations, dbt tests, and custom validators.
-- Each check references a pipeline run for traceability.
CREATE TABLE IF NOT EXISTS pipeline.quality_checks (
    id SERIAL PRIMARY KEY,
    run_id INTEGER REFERENCES pipeline.runs(id),
    check_name VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    layer VARCHAR(10) DEFAULT 'bronze',
    passed BOOLEAN NOT NULL,
    metric_value DOUBLE PRECISION,
    threshold DOUBLE PRECISION,
    details JSONB DEFAULT '{}',
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quality_checks_run ON pipeline.quality_checks(run_id);
CREATE INDEX IF NOT EXISTS idx_quality_checks_table ON pipeline.quality_checks(table_name, checked_at DESC);

-- ============================================================================
-- Prediction Results (mutable — supports user feedback, actuals backfill)
-- ============================================================================
-- Predictions are stored here (OLTP) for CRUD operations, then synced to
-- ClickHouse (OLAP) via Debezium CDC for dashboard analytics.
CREATE TABLE IF NOT EXISTS pipeline.predictions (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(20) NOT NULL,
    predicted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    target_timestamp TIMESTAMPTZ NOT NULL,
    predicted_price DOUBLE PRECISION,
    predicted_direction VARCHAR(10),
    confidence DOUBLE PRECISION,
    model_version VARCHAR(50),
    actual_price DOUBLE PRECISION,
    feedback VARCHAR(20)
);

CREATE INDEX IF NOT EXISTS idx_predictions_symbol_time ON pipeline.predictions(symbol, predicted_at DESC);

-- ============================================================================
-- Publication for Debezium CDC
-- ============================================================================
-- All tables in pipeline schema are published for CDC replication.
-- Debezium captures INSERT/UPDATE/DELETE and streams to Kafka.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'pipeline_pub') THEN
        EXECUTE 'CREATE PUBLICATION pipeline_pub FOR TABLES IN SCHEMA pipeline';
    END IF;
END
$$;
