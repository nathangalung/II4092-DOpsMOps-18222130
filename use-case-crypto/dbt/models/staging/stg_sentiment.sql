-- Deduplicated sentiment data by symbol + timestamp + source
SELECT
    symbol,
    timestamp,
    source,
    sentiment_score,
    raw_data
FROM {{ source('bronze', 'crypto_sentiment') }}
ORDER BY symbol, timestamp, source, created_at DESC
LIMIT 1 BY symbol, timestamp, source
