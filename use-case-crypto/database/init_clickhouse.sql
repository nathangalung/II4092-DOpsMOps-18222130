-- ============================================================================
-- Crypto Use Case — ClickHouse Database Initialization
-- ============================================================================
-- MEDALLION ARCHITECTURE: Bronze → Silver → Gold
--
--   Bronze: Raw data from Kafka (append-only, no transforms, source of truth)
--   Silver: Validated, deduplicated (populated by dbt staging models)
--   Gold:   ML-ready features, aggregations (populated by dbt mart models)
--   Features: Backward-compat alias views → bronze/gold (existing services work unchanged)
--
-- TEMPLATE: When creating a new use case, replace 'crypto_' table prefix
-- with your domain prefix (e.g., 'stock_'). Modify column definitions to
-- match your domain data schema. Keep drift_metrics, model_metrics, and
-- data_quality_* tables as-is (they are domain-agnostic).
-- ============================================================================

-- ============================================================================
-- CREATE DATABASES (Medallion Layers)
-- ============================================================================
CREATE DATABASE IF NOT EXISTS bronze;
CREATE DATABASE IF NOT EXISTS silver;
CREATE DATABASE IF NOT EXISTS gold;
CREATE DATABASE IF NOT EXISTS features;

-- ############################################################################
--                          BRONZE LAYER (Raw)
-- ############################################################################
-- Raw data exactly as received from Kafka. Append-only, no transforms.
-- Kafka engines write here. This is the "source of truth" — can always
-- reprocess silver/gold from bronze.
-- ############################################################################

-- ============================================================================
-- Bronze: Raw OHLCV Data (from crypto.validated topic)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bronze.crypto_ohlcv (
    symbol String,
    timestamp DateTime64(3),
    date Date DEFAULT toDate(timestamp),
    hour UInt8 DEFAULT toHour(timestamp),
    open Float64,
    high Float64,
    low Float64,
    close Float64,
    volume Float64,
    data_type LowCardinality(String) DEFAULT 'historical',
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY (symbol, timestamp)
PARTITION BY toYYYYMM(timestamp);

-- Kafka Engine: crypto.validated → bronze.crypto_ohlcv
-- Broker, SASL_SSL credentials, and security_protocol live in the
-- `kafka_crypto` NAMED COLLECTION created by the `clickhouse-init` Job
-- (manifests/base/clickhouse-init.yaml) BEFORE this DDL runs. Each table
-- below only overrides topic/group/format — no auth in this file, no
-- broker hardcoded here either.
CREATE TABLE IF NOT EXISTS bronze.crypto_ohlcv_kafka (
    symbol String,
    timestamp String,
    open Float64,
    high Float64,
    low Float64,
    close Float64,
    volume Float64,
    source String
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'crypto.validated',
         kafka_group_name = 'clickhouse_bronze_ohlcv',
         kafka_format = 'JSONEachRow',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS bronze.crypto_ohlcv_consumer TO bronze.crypto_ohlcv AS
SELECT
    symbol,
    parseDateTimeBestEffort(timestamp) AS timestamp,
    open, high, low, close, volume
FROM bronze.crypto_ohlcv_kafka
WHERE open > 0 AND close > 0;

-- ============================================================================
-- Bronze: Raw Sentiment Data (from crypto.supplementary topic)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bronze.crypto_sentiment (
    symbol String,
    timestamp DateTime64(3),
    source LowCardinality(String),
    sentiment_score Float64,
    sentiment_label LowCardinality(String),
    volume Int64,
    raw_data String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, source, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY;

CREATE TABLE IF NOT EXISTS bronze.crypto_sentiment_kafka (
    symbol String,
    timestamp String,
    source String,
    title String,
    score Float64,
    url String
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'crypto.supplementary',
         kafka_group_name = 'clickhouse_bronze_sentiment',
         kafka_format = 'JSONEachRow',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS bronze.crypto_sentiment_consumer TO bronze.crypto_sentiment AS
SELECT
    symbol,
    parseDateTimeBestEffort(timestamp) AS timestamp,
    source,
    score AS sentiment_score,
    multiIf(score > 0.6, 'positive', score < 0.4, 'negative', 'neutral') AS sentiment_label,
    0 AS volume,
    title AS raw_data
FROM bronze.crypto_sentiment_kafka;

-- ============================================================================
-- Bronze: Stream-Computed Features (from crypto.features.v1 topic)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bronze.crypto_ohlcv_features (
    symbol String,
    timestamp DateTime64(3),
    date Date DEFAULT toDate(timestamp),
    hour UInt8 DEFAULT toHour(timestamp),
    open Float64,
    high Float64,
    low Float64,
    close Float64,
    volume Float64,
    data_type LowCardinality(String) DEFAULT 'historical',
    sma_20 Float64 DEFAULT 0,
    sma_50 Float64 DEFAULT 0,
    ema_12 Float64 DEFAULT 0,
    ema_26 Float64 DEFAULT 0,
    macd Float64 DEFAULT 0,
    macd_signal Float64 DEFAULT 0,
    rsi_14 Float64 DEFAULT 0,
    rsi_7 Float64 DEFAULT 0,
    stoch_k Float64 DEFAULT 0,
    stoch_d Float64 DEFAULT 0,
    williams_r Float64 DEFAULT 0,
    roc_10 Float64 DEFAULT 0,
    bb_upper Float64 DEFAULT 0,
    bb_lower Float64 DEFAULT 0,
    bb_width Float64 DEFAULT 0,
    atr_14 Float64 DEFAULT 0,
    adx Float64 DEFAULT 0,
    obv Float64 DEFAULT 0,
    mfi_14 Float64 DEFAULT 0,
    vwap Float64 DEFAULT 0,
    return_1h Float64 DEFAULT 0,
    return_24h Float64 DEFAULT 0,
    volatility_24h Float64 DEFAULT 0,
    rolling_mean_7 Float64 DEFAULT 0,
    rolling_mean_14 Float64 DEFAULT 0,
    rolling_ema_12 Float64 DEFAULT 0,
    rolling_ema_26 Float64 DEFAULT 0,
    momentum_14 Float64 DEFAULT 0,
    trend_convergence Float64 DEFAULT 0,
    trend_signal Float64 DEFAULT 0,
    band_upper Float64 DEFAULT 0,
    band_lower Float64 DEFAULT 0,
    dispersion Float64 DEFAULT 0,
    value_change Float64 DEFAULT 0,
    secondary_avg Float64 DEFAULT 0,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY (symbol, timestamp)
PARTITION BY toYYYYMM(timestamp);

CREATE TABLE IF NOT EXISTS bronze.crypto_features_kafka (
    symbol String,
    timestamp String,
    open Float64,
    high Float64,
    low Float64,
    close Float64,
    volume Float64,
    source String,
    rolling_mean_7 Float64,
    rolling_mean_14 Float64,
    rolling_ema_12 Float64,
    rolling_ema_26 Float64,
    momentum_14 Float64,
    trend_convergence Float64,
    trend_signal Float64,
    band_upper Float64,
    band_lower Float64,
    dispersion Float64,
    value_change Float64,
    secondary_avg Float64
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'crypto.features.v1',
         kafka_group_name = 'clickhouse_bronze_features',
         kafka_format = 'JSONEachRow',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS bronze.crypto_features_consumer TO bronze.crypto_ohlcv_features AS
SELECT
    symbol,
    parseDateTimeBestEffort(timestamp) AS timestamp,
    open, high, low, close, volume,
    rolling_mean_7, rolling_mean_14,
    rolling_ema_12, rolling_ema_26,
    momentum_14, trend_convergence, trend_signal,
    band_upper, band_lower,
    dispersion, value_change, secondary_avg
FROM bronze.crypto_features_kafka;

-- ============================================================================
-- Bronze: Ticker Data (from crypto.validated topic, price > 0, open = 0)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bronze.crypto_tickers (
    symbol String,
    timestamp DateTime64(3),
    date Date DEFAULT toDate(timestamp),
    price Float64,
    bid Float64,
    ask Float64,
    spread Float64,
    volume Float64,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, timestamp)
TTL toDateTime(timestamp) + INTERVAL 30 DAY;

CREATE TABLE IF NOT EXISTS bronze.crypto_tickers_kafka (
    symbol String,
    timestamp String,
    price Float64,
    bid Float64,
    ask Float64,
    volume Float64,
    volume_24h Float64,
    open Float64,
    source String
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'crypto.validated',
         kafka_group_name = 'clickhouse_bronze_tickers',
         kafka_format = 'JSONEachRow',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS bronze.crypto_tickers_consumer TO bronze.crypto_tickers AS
SELECT
    symbol,
    parseDateTimeBestEffort(timestamp) AS timestamp,
    price,
    bid,
    ask,
    if(ask > 0 AND bid > 0, ask - bid, 0) AS spread,
    if(volume > 0, volume, volume_24h) AS volume
FROM bronze.crypto_tickers_kafka
WHERE price > 0 AND open = 0;

-- ============================================================================
-- Bronze: Trade Data (from crypto.trades.v1 topic)
-- ============================================================================
CREATE TABLE IF NOT EXISTS bronze.crypto_trades (
    symbol String,
    trade_id String,
    timestamp DateTime64(3),
    date Date DEFAULT toDate(timestamp),
    price Float64,
    size Float64,
    side String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY (symbol, trade_id, timestamp)
TTL toDateTime(timestamp) + INTERVAL 7 DAY;

CREATE TABLE IF NOT EXISTS bronze.crypto_trades_kafka (
    symbol String,
    timestamp String,
    price Float64,
    size Float64,
    side Float64,
    trade_id Float64,
    source String
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'crypto.trades.v1',
         kafka_group_name = 'clickhouse_bronze_trades',
         kafka_format = 'JSONEachRow',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS bronze.crypto_trades_consumer TO bronze.crypto_trades AS
SELECT
    symbol,
    toString(toInt64(trade_id)) AS trade_id,
    parseDateTimeBestEffort(timestamp) AS timestamp,
    price,
    size,
    if(side > 0, 'buy', 'sell') AS side
FROM bronze.crypto_trades_kafka;

-- ############################################################################
--                          BRONZE LAYER (Domain-Agnostic Tables)
-- ############################################################################
-- These tables are used by all use-cases (drift, model metrics, quality).

CREATE TABLE IF NOT EXISTS bronze.crypto_embeddings (
    symbol String,
    timestamp DateTime64(3),
    embedding_type LowCardinality(String),
    embedding Array(Float32),
    source_text String,
    model_name String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, embedding_type, timestamp)
TTL toDateTime(timestamp) + INTERVAL 30 DAY;

-- ############################################################################
--                        GOLD LAYER (ML-Ready)
-- ############################################################################
-- Populated by dbt mart models OR batch Python jobs.
-- Contains aggregated features, training views, predictions.
-- ############################################################################

-- ============================================================================
-- Gold: Aggregated Sentiment Features (populated by batch-sentiment job)
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.crypto_sentiment_features (
    symbol String,
    timestamp DateTime64(3),
    window_hours UInt8,
    news_count Int32,
    avg_sentiment Float64,
    sentiment_std Float64,
    positive_ratio Float64,
    sentiment_momentum Float64,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY (symbol, timestamp, window_hours)
PARTITION BY toYYYYMM(timestamp);

-- ============================================================================
-- Gold: Fear & Greed Index (populated by batch-sentiment job)
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.fear_greed_index (
    timestamp DateTime64(3),
    value UInt8,
    value_classification LowCardinality(String),
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY timestamp;

-- ============================================================================
-- Gold: Predictions (from serving/inference — Train+)
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.crypto_predictions (
    symbol String,
    prediction_timestamp DateTime64(3),
    target_timestamp DateTime64(3),
    predicted_price Float64,
    predicted_direction String,
    predicted_volatility Float64,
    confidence Float64,
    model_version String,
    model_type String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedReplacingMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}', created_at)
ORDER BY (symbol, prediction_timestamp);

-- ============================================================================
-- CDC Kafka Engine: PostgreSQL predictions → Gold predictions
-- ============================================================================
-- Consumes Debezium CDC events from cdc.pipeline.predictions topic.
-- Debezium JSON: {"before":null,"after":{"symbol":"BTC",...},"op":"c"}
-- Uses JSONAsString + JSONExtract for nested field access.
CREATE TABLE IF NOT EXISTS gold.cdc_predictions_kafka (
    message String
) ENGINE = Kafka(kafka_crypto)
SETTINGS kafka_topic_list = 'cdc.pipeline.predictions',
         kafka_group_name = 'clickhouse_cdc_predictions',
         kafka_format = 'JSONAsString',
         kafka_num_consumers = 1;

CREATE MATERIALIZED VIEW IF NOT EXISTS gold.cdc_predictions_consumer TO gold.crypto_predictions AS
SELECT
    JSONExtractString(message, 'after', 'symbol') AS symbol,
    parseDateTimeBestEffort(JSONExtractString(message, 'after', 'predicted_at')) AS prediction_timestamp,
    parseDateTimeBestEffort(JSONExtractString(message, 'after', 'target_timestamp')) AS target_timestamp,
    JSONExtractFloat(message, 'after', 'predicted_price') AS predicted_price,
    JSONExtractString(message, 'after', 'predicted_direction') AS predicted_direction,
    JSONExtractFloat(message, 'after', 'predicted_volatility') AS predicted_volatility,
    JSONExtractFloat(message, 'after', 'confidence') AS confidence,
    JSONExtractString(message, 'after', 'model_version') AS model_version,
    JSONExtractString(message, 'after', 'model_type') AS model_type
FROM gold.cdc_predictions_kafka
WHERE JSONExtractString(message, 'op') IN ('c', 'u', 'r')
  AND JSONExtractString(message, 'after', 'symbol') != '';

-- ============================================================================
-- Gold: Model Training Metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.model_metrics (
    run_id String,
    model_name String,
    model_type String,
    symbol String,
    timestamp DateTime64(3),
    rmse Float64,
    mae Float64,
    r2 Float64,
    training_samples Int64,
    validation_samples Int64,
    feature_count Int64,
    training_reason String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (model_name, timestamp);

-- ============================================================================
-- Gold: Drift Detection Metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.drift_metrics (
    symbol String,
    timestamp DateTime64(3),
    feature_name String,
    psi Float64,
    ks_statistic Float64,
    ks_pvalue Float64,
    drift_detected UInt8,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, timestamp, feature_name);

CREATE TABLE IF NOT EXISTS gold.drift_multi_scale (
    symbol String,
    timestamp DateTime64(3),
    scale LowCardinality(String),
    feature_name String,
    psi_value Float64,
    ks_statistic Float64,
    ks_pvalue Float64,
    drift_detected UInt8,
    severity LowCardinality(String),
    trigger_retrain UInt8,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, scale, timestamp, feature_name);

-- ============================================================================
-- Gold: Data Quality Metrics
-- ============================================================================
CREATE TABLE IF NOT EXISTS gold.data_quality_metrics (
    timestamp DateTime64(3),
    table_name String,
    metric_name String,
    metric_value Float64,
    threshold Float64,
    passed UInt8,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (table_name, timestamp);

CREATE TABLE IF NOT EXISTS gold.data_quality_expectations (
    timestamp DateTime64(3),
    data_type LowCardinality(String),
    expectation String,
    success UInt8,
    details String,
    created_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (data_type, timestamp);

CREATE TABLE IF NOT EXISTS gold.quality_outliers (
    symbol String,
    timestamp DateTime64(3),
    column_name String,
    value Float64,
    z_score Float64,
    detected_at DateTime DEFAULT now()
) ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, timestamp, column_name);

-- ############################################################################
--                   FEATURES DATABASE (Backward Compatibility)
-- ############################################################################
-- Views that redirect queries from existing services (ConfigMaps, Feast,
-- batch jobs) to the appropriate Medallion layer.
-- Existing services query features.* — these views make that work unchanged.
-- ############################################################################

-- Bronze data accessed via features.*
CREATE OR REPLACE VIEW features.crypto_ohlcv AS SELECT * FROM bronze.crypto_ohlcv;
CREATE OR REPLACE VIEW features.crypto_sentiment AS SELECT * FROM bronze.crypto_sentiment;
CREATE OR REPLACE VIEW features.crypto_tickers AS SELECT * FROM bronze.crypto_tickers;
CREATE OR REPLACE VIEW features.crypto_trades AS SELECT * FROM bronze.crypto_trades;
CREATE OR REPLACE VIEW features.crypto_ohlcv_features AS SELECT * FROM bronze.crypto_ohlcv_features;
CREATE OR REPLACE VIEW features.crypto_embeddings AS SELECT * FROM bronze.crypto_embeddings;

-- Gold data accessed via features.*
-- IMPORTANT: ClickHouse Views are READ-ONLY; writers (GE analyzer, drift
-- reporter, evidently) MUST target `gold.<table>` directly.  These views
-- exist only for BI tools / dbt gold marts that query `features.*`.
-- The previous implementation pointed writers at these views and failed
-- at runtime with "Method write is not supported by storage View".
CREATE OR REPLACE VIEW features.crypto_sentiment_features AS SELECT * FROM gold.crypto_sentiment_features;
CREATE OR REPLACE VIEW features.fear_greed_index AS SELECT * FROM gold.fear_greed_index;
CREATE OR REPLACE VIEW features.crypto_predictions AS SELECT * FROM gold.crypto_predictions;
CREATE OR REPLACE VIEW features.model_metrics AS SELECT * FROM gold.model_metrics;
CREATE OR REPLACE VIEW features.drift_metrics AS SELECT * FROM gold.drift_metrics;
CREATE OR REPLACE VIEW features.drift_multi_scale AS SELECT * FROM gold.drift_multi_scale;
CREATE OR REPLACE VIEW features.data_quality_metrics AS SELECT * FROM gold.data_quality_metrics;
CREATE OR REPLACE VIEW features.data_quality_expectations AS SELECT * FROM gold.data_quality_expectations;
CREATE OR REPLACE VIEW features.quality_outliers AS SELECT * FROM gold.quality_outliers;

-- ============================================================================
-- Write-through aliases: writable "features.*" points to the gold table via
-- a materialized view, so services that were hardcoded to write to
-- `features.data_quality_*` keep working without code changes.
--
-- Pattern: Null-engine staging table + Materialized View that funnels
-- INSERTs into the backing gold.<table>.  This is the ClickHouse-idiomatic
-- way to make a read-only VIEW-like surface behave as writable.
-- ============================================================================
CREATE TABLE IF NOT EXISTS features.quality_write_buffer (
    timestamp DateTime64(3),
    data_type LowCardinality(String),
    expectation String,
    success UInt8,
    details String,
    created_at DateTime DEFAULT now()
) ENGINE = Null;

CREATE MATERIALIZED VIEW IF NOT EXISTS features.data_quality_expectations_mv
TO gold.data_quality_expectations
AS SELECT timestamp, data_type, expectation, success, details, created_at
FROM features.quality_write_buffer;

-- ============================================================================
-- Combined Features View (OHLCV + Technical + Sentiment)
-- ============================================================================
CREATE OR REPLACE VIEW features.crypto_features_full AS
SELECT
    o.symbol,
    o.timestamp,
    o.open, o.high, o.low, o.close, o.volume,
    o.sma_20, o.sma_50, o.ema_12, o.ema_26,
    o.macd, o.macd_signal,
    o.rsi_14, o.rsi_7, o.stoch_k, o.stoch_d, o.williams_r, o.roc_10,
    o.bb_upper, o.bb_lower, o.bb_width, o.atr_14,
    o.adx, o.obv, o.mfi_14, o.vwap,
    o.return_1h, o.return_24h, o.volatility_24h,
    s1.news_count AS news_count_1h,
    s1.avg_sentiment AS sentiment_1h,
    s1.sentiment_momentum AS sentiment_momentum_1h,
    s6.news_count AS news_count_6h,
    s6.avg_sentiment AS sentiment_6h,
    s6.sentiment_momentum AS sentiment_momentum_6h,
    s24.news_count AS news_count_24h,
    s24.avg_sentiment AS sentiment_24h,
    s24.positive_ratio AS positive_ratio_24h,
    s24.sentiment_momentum AS sentiment_momentum_24h
FROM bronze.crypto_ohlcv_features o
LEFT JOIN gold.crypto_sentiment_features s1
    ON o.symbol = s1.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s1.timestamp)
    AND s1.window_hours = 1
LEFT JOIN gold.crypto_sentiment_features s6
    ON o.symbol = s6.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s6.timestamp)
    AND s6.window_hours = 6
LEFT JOIN gold.crypto_sentiment_features s24
    ON o.symbol = s24.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s24.timestamp)
    AND s24.window_hours = 24;

-- ============================================================================
-- Training Features View (OHLCV + Technical + Sentiment + Fear&Greed)
-- ============================================================================
CREATE OR REPLACE VIEW features.crypto_training_features AS
SELECT
    o.symbol,
    o.timestamp,
    o.open, o.high, o.low, o.close, o.volume,
    o.sma_20, o.sma_50, o.ema_12, o.ema_26,
    o.macd, o.macd_signal,
    o.rsi_14, o.rsi_7, o.stoch_k, o.stoch_d, o.williams_r, o.roc_10,
    o.bb_upper, o.bb_lower, o.bb_width, o.atr_14,
    o.adx, o.obv, o.mfi_14, o.vwap,
    o.return_1h, o.return_24h, o.volatility_24h,
    o.rolling_mean_7, o.rolling_mean_14,
    o.rolling_ema_12, o.rolling_ema_26,
    o.momentum_14, o.trend_convergence, o.trend_signal,
    o.band_upper, o.band_lower, o.dispersion, o.value_change, o.secondary_avg,
    s1.news_count AS news_count_1h,
    s1.avg_sentiment AS sentiment_1h,
    s1.sentiment_momentum AS sentiment_momentum_1h,
    s6.news_count AS news_count_6h,
    s6.avg_sentiment AS sentiment_6h,
    s6.sentiment_momentum AS sentiment_momentum_6h,
    s24.news_count AS news_count_24h,
    s24.avg_sentiment AS sentiment_24h,
    s24.positive_ratio AS positive_ratio_24h,
    s24.sentiment_momentum AS sentiment_momentum_24h,
    fg.value AS fear_greed_value,
    fg.value_classification AS fear_greed_label
FROM bronze.crypto_ohlcv_features o
LEFT JOIN gold.crypto_sentiment_features s1
    ON o.symbol = s1.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s1.timestamp)
    AND s1.window_hours = 1
LEFT JOIN gold.crypto_sentiment_features s6
    ON o.symbol = s6.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s6.timestamp)
    AND s6.window_hours = 6
LEFT JOIN gold.crypto_sentiment_features s24
    ON o.symbol = s24.symbol
    AND toStartOfHour(o.timestamp) = toStartOfHour(s24.timestamp)
    AND s24.window_hours = 24
LEFT JOIN gold.fear_greed_index fg
    ON toDate(o.timestamp) = toDate(fg.timestamp);

-- ============================================================================
-- Train/Validation Materialized Views
-- ============================================================================
CREATE MATERIALIZED VIEW IF NOT EXISTS gold.train_data
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, timestamp)
AS SELECT *
FROM bronze.crypto_ohlcv_features
WHERE data_type = 'train';

CREATE MATERIALIZED VIEW IF NOT EXISTS gold.validation_data
ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/{table}', '{replica}')
ORDER BY (symbol, timestamp)
AS SELECT *
FROM bronze.crypto_ohlcv_features
WHERE data_type = 'validation';

-- Note: train_data and validation_data MVs write to their own internal storage
-- in the gold database. Access them directly via gold.train_data / gold.validation_data.

-- ============================================================================
-- Helper View: Data Summary by Type
-- ============================================================================
CREATE OR REPLACE VIEW features.data_summary AS
SELECT
    data_type,
    symbol,
    count(*) as record_count,
    min(timestamp) as min_timestamp,
    max(timestamp) as max_timestamp,
    min(date) as min_date,
    max(date) as max_date
FROM bronze.crypto_ohlcv_features
GROUP BY data_type, symbol
ORDER BY data_type, symbol;
