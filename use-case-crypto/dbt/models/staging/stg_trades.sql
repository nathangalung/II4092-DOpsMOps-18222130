-- Deduplicated trade data by trade_id
SELECT
    symbol,
    trade_id,
    timestamp,
    toDate(timestamp) AS date,
    price, size, side
FROM {{ source('bronze', 'crypto_trades') }}
WHERE price > 0 AND size > 0
ORDER BY symbol, trade_id, created_at DESC
LIMIT 1 BY symbol, trade_id
