-- Daily Fear & Greed index values extracted from sentiment data
-- Deduplicates to one value per day
SELECT
    toDate(timestamp) AS date,
    toUInt8(sentiment_score) AS value,
    extractAll(raw_data, '\\(([^)]+)\\)')[1] AS value_classification
FROM {{ ref('stg_sentiment') }}
WHERE source = 'fear-greed'
ORDER BY timestamp DESC
LIMIT 1 BY toDate(timestamp)
