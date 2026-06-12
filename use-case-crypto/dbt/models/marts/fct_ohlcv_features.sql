-- OHLCV technical-indicator feature mart — the BATCH counterpart of the Flink
-- stream feature set (schema.yaml STREAM_FEATURES_ALL). Computes the full
-- technical-analysis matrix with ClickHouse window functions so the training
-- table carries momentum / trend / volatility / volume indicators (RSI, MACD,
-- Bollinger Bands, ATR, Stochastic, Williams %R, ROC, momentum, OBV) rather
-- than raw OHLCV + moving averages alone. Computing the same indicators here as
-- the stream path is what makes batch↔stream parity (KF-11) measurable.
--
-- Layered CTEs: several indicators need a per-row delta / true-range / signed
-- volume first (`base`), then a rolling aggregate over it (`ind`), then a final
-- pass for signal lines that smooth an already-computed indicator (MACD signal,
-- Stochastic %D). EMA is a finite-window exponential weighting (the array idiom)
-- because ClickHouse has no per-row windowed EMA; over N+ rows the truncated
-- tail weight is negligible.
WITH base AS (
    SELECT
        symbol, timestamp, date, hour,
        open, high, low, close, volume,
        lagInFrame(close, 1) OVER w AS prev_close,
        greatest(close - lagInFrame(close, 1) OVER w, 0) AS gain,
        greatest(lagInFrame(close, 1) OVER w - close, 0) AS loss,
        greatest(
            high - low,
            abs(high - lagInFrame(close, 1) OVER w),
            abs(low  - lagInFrame(close, 1) OVER w)
        ) AS true_range,
        multiIf(
            close > lagInFrame(close, 1) OVER w,  volume,
            close < lagInFrame(close, 1) OVER w, -volume,
            0
        ) AS signed_volume
    FROM {{ ref('stg_ohlcv') }}
    WINDOW w AS (PARTITION BY symbol ORDER BY timestamp)
),
ind AS (
    SELECT
        symbol, timestamp, date, hour,
        open, high, low, close, volume,
        -- Moving averages
        avg(close) OVER w20 AS sma_20,
        avg(close) OVER w50 AS sma_50,
        -- Volume SMA (20) — the batch↔stream parity anchor (KF-11/SK-F-11).
        -- MUST mirror the stream side exactly: Flink's Indicators.rollingMean
        -- over the secondary (volume) field with FLINK_SECONDARY_AVG_PERIOD=20
        -- (configmaps/features.yaml) emits `secondary_avg` into
        -- bronze.crypto_ohlcv_features; both are a trailing mean over the last
        -- 20 events INCLUDING the current row, per symbol, event-time order.
        -- experiments/parity/parity-check.sh asserts the two columns agree.
        avg(volume) OVER w20 AS volume_sma_20,
        -- EMA (finite-window exponential weighting, beta = 1 - 2/(N+1);
        -- current row reversed to index 0 so it carries the highest weight)
        arraySum(arrayMap((v, k) -> v * pow(1 - 2.0 / 13, k),
            arrayReverse(groupArray(close) OVER w12),
            range(length(groupArray(close) OVER w12))))
          / arraySum(arrayMap(k -> pow(1 - 2.0 / 13, k),
            range(length(groupArray(close) OVER w12)))) AS ema_12,
        arraySum(arrayMap((v, k) -> v * pow(1 - 2.0 / 27, k),
            arrayReverse(groupArray(close) OVER w26),
            range(length(groupArray(close) OVER w26))))
          / arraySum(arrayMap(k -> pow(1 - 2.0 / 27, k),
            range(length(groupArray(close) OVER w26)))) AS ema_26,
        -- Returns / rate-of-change / momentum
        if(prev_close > 0, (close - prev_close) / prev_close, 0) AS return_1h,
        if(lagInFrame(close, 24) OVER w > 0,
           (close - lagInFrame(close, 24) OVER w) / lagInFrame(close, 24) OVER w, 0) AS return_24h,
        if(lagInFrame(close, 10) OVER w > 0,
           (close - lagInFrame(close, 10) OVER w) / lagInFrame(close, 10) OVER w * 100, 0) AS roc_10,
        close - lagInFrame(close, 14) OVER w AS momentum_14,
        -- Volatility (coefficient of variation over 24 periods)
        if(avg(close) OVER w24 > 0,
           stddevPop(close) OVER w24 / avg(close) OVER w24, 0) AS volatility_24h,
        -- RSI (Cutler / SMA variant): 100 - 100/(1 + avgGain/avgLoss)
        100 - 100 / (1 + avg(gain) OVER w14 / nullIf(avg(loss) OVER w14, 0)) AS rsi_14,
        100 - 100 / (1 + avg(gain) OVER w7  / nullIf(avg(loss) OVER w7,  0)) AS rsi_7,
        -- Bollinger Bands (20, 2σ) + normalised width
        avg(close) OVER w20 + 2 * stddevPop(close) OVER w20 AS bb_upper,
        avg(close) OVER w20 - 2 * stddevPop(close) OVER w20 AS bb_lower,
        if(avg(close) OVER w20 > 0,
           4 * stddevPop(close) OVER w20 / avg(close) OVER w20, 0) AS bb_width,
        -- Average True Range (14)
        avg(true_range) OVER w14 AS atr_14,
        -- Stochastic %K (14) and Williams %R (14) over the same hi/lo channel
        if(max(high) OVER w14 - min(low) OVER w14 > 0,
           100 * (close - min(low) OVER w14) / (max(high) OVER w14 - min(low) OVER w14), 50) AS stoch_k,
        if(max(high) OVER w14 - min(low) OVER w14 > 0,
           -100 * (max(high) OVER w14 - close) / (max(high) OVER w14 - min(low) OVER w14), -50) AS williams_r,
        -- On-Balance Volume (cumulative signed volume)
        sum(signed_volume) OVER w AS obv
    FROM base
    WINDOW
        w   AS (PARTITION BY symbol ORDER BY timestamp),
        w7  AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 6  PRECEDING AND CURRENT ROW),
        w12 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 11 PRECEDING AND CURRENT ROW),
        w14 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
        w20 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
        w24 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 23 PRECEDING AND CURRENT ROW),
        w26 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 25 PRECEDING AND CURRENT ROW),
        w50 AS (PARTITION BY symbol ORDER BY timestamp ROWS BETWEEN 49 PRECEDING AND CURRENT ROW)
)
SELECT
    symbol, timestamp, date, hour,
    open, high, low, close, volume,
    sma_20, sma_50, volume_sma_20, ema_12, ema_26,
    -- MACD line + signal (signal = SMA(9) of MACD; a stable, common signal-line
    -- form — avoids a second recursive EMA over an already-approximated EMA)
    ema_12 - ema_26 AS macd,
    avg(ema_12 - ema_26) OVER (PARTITION BY symbol ORDER BY timestamp
        ROWS BETWEEN 8 PRECEDING AND CURRENT ROW) AS macd_signal,
    return_1h, return_24h, roc_10, momentum_14, volatility_24h,
    rsi_14, rsi_7, bb_upper, bb_lower, bb_width, atr_14,
    stoch_k,
    avg(stoch_k) OVER (PARTITION BY symbol ORDER BY timestamp
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS stoch_d,
    williams_r, obv
FROM ind
