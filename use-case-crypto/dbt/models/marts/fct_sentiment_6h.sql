{{ config(materialized='table') }}

SELECT symbol, timestamp, news_count, avg_sentiment, sentiment_std, positive_ratio
FROM {{ ref('fct_sentiment_agg') }}
WHERE window_hours = 6
