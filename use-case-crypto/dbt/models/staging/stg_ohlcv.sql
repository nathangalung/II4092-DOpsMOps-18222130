-- Deduplicated, validated OHLCV candle data
-- Bronze → Silver: removes duplicates, filters invalid records
SELECT
    symbol,
    timestamp,
    toDate(timestamp) AS date,
    toHour(timestamp) AS hour,
    open, high, low, close, volume
FROM {{ source('bronze', 'crypto_ohlcv') }}
WHERE open > 0 AND close > 0 AND volume >= 0
  AND high >= low
ORDER BY symbol, timestamp, created_at DESC
LIMIT 1 BY symbol, timestamp
