-- Deduplicated ticker snapshots (price, bid, ask)
SELECT
    symbol,
    timestamp,
    toDate(timestamp) AS date,
    price, bid, ask, spread, volume
FROM {{ source('bronze', 'crypto_tickers') }}
WHERE price > 0
ORDER BY symbol, timestamp, created_at DESC
LIMIT 1 BY symbol, timestamp
