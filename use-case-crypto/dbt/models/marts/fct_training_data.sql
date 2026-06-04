-- Combined training dataset: OHLCV features + sentiment windows + Fear & Greed
-- Each sentiment window is a separate materialized table to avoid ClickHouse
-- multi-JOIN ambiguity with the same source table.
-- ClickHouse adapter materialises qualified identifiers (`o.symbol`) as
-- literal column names, which then breaks downstream `SELECT symbol`.
-- Always alias qualified columns to their bare contract name (see _models.yml).
SELECT
    o.symbol AS symbol,
    o.timestamp AS timestamp,
    o.date AS date,
    o.hour AS hour,
    o.open AS open,
    o.high AS high,
    o.low AS low,
    o.close AS close,
    o.volume AS volume,
    o.sma_20 AS sma_20,
    o.sma_50 AS sma_50,
    o.ema_12 AS ema_12,
    o.ema_26 AS ema_26,
    o.macd AS macd,
    o.macd_signal AS macd_signal,
    o.return_1h AS return_1h,
    o.return_24h AS return_24h,
    o.roc_10 AS roc_10,
    o.momentum_14 AS momentum_14,
    o.volatility_24h AS volatility_24h,
    o.rsi_14 AS rsi_14,
    o.rsi_7 AS rsi_7,
    o.bb_upper AS bb_upper,
    o.bb_lower AS bb_lower,
    o.bb_width AS bb_width,
    o.atr_14 AS atr_14,
    o.stoch_k AS stoch_k,
    o.stoch_d AS stoch_d,
    o.williams_r AS williams_r,
    o.obv AS obv,
    s1.news_count AS news_count_1h,
    s1.avg_sentiment AS sentiment_1h,
    s6.news_count AS news_count_6h,
    s6.avg_sentiment AS sentiment_6h,
    s24.news_count AS news_count_24h,
    s24.avg_sentiment AS sentiment_24h,
    s24.positive_ratio AS positive_ratio_24h,
    fg.value AS fear_greed_value,
    fg.value_classification AS fear_greed_label
FROM {{ ref('fct_ohlcv_features') }} AS o
LEFT JOIN {{ ref('fct_sentiment_1h') }} AS s1
    ON o.symbol = s1.symbol AND o.timestamp = s1.timestamp
LEFT JOIN {{ ref('fct_sentiment_6h') }} AS s6
    ON o.symbol = s6.symbol AND o.timestamp = s6.timestamp
LEFT JOIN {{ ref('fct_sentiment_24h') }} AS s24
    ON o.symbol = s24.symbol AND o.timestamp = s24.timestamp
LEFT JOIN {{ ref('dim_fear_greed') }} AS fg
    ON o.date = fg.date
