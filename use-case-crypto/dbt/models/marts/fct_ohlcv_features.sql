-- OHLCV with computed moving averages and returns
-- Uses ClickHouse window functions for efficient computation
SELECT
    symbol, timestamp, date, hour,
    open, high, low, close, volume,
    -- Simple Moving Averages
    avg(close) OVER (PARTITION BY symbol ORDER BY timestamp
        ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS sma_20,
    avg(close) OVER (PARTITION BY symbol ORDER BY timestamp
        ROWS BETWEEN 49 PRECEDING AND CURRENT ROW) AS sma_50,
    -- Returns
    if(lagInFrame(close, 1) OVER w > 0,
       (close - lagInFrame(close, 1) OVER w) / lagInFrame(close, 1) OVER w,
       0) AS return_1h,
    if(lagInFrame(close, 24) OVER w > 0,
       (close - lagInFrame(close, 24) OVER w) / lagInFrame(close, 24) OVER w,
       0) AS return_24h,
    -- Volatility (coefficient of variation over 24 periods)
    if(avg(close) OVER w24 > 0,
       stddevPop(close) OVER w24 / avg(close) OVER w24,
       0) AS volatility_24h
FROM {{ ref('stg_ohlcv') }}
WINDOW
    w AS (PARTITION BY symbol ORDER BY timestamp),
    w24 AS (PARTITION BY symbol ORDER BY timestamp
        ROWS BETWEEN 23 PRECEDING AND CURRENT ROW)
