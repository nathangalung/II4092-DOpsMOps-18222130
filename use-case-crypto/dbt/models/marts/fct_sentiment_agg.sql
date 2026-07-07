-- Windowed sentiment aggregations at 1h, 6h, 24h windows
-- Computed per OHLCV timestamp to align with price data
SELECT
    o.symbol AS symbol,
    o.timestamp AS timestamp,
    w.window_hours AS window_hours,
    count(s.sentiment_score) AS news_count,
    if(count(s.sentiment_score) > 0, avg(s.sentiment_score), 0) AS avg_sentiment,
    if(count(s.sentiment_score) > 1, stddevPop(s.sentiment_score), 0) AS sentiment_std,
    if(count(s.sentiment_score) > 0,
       countIf(s.sentiment_score > 0.6) / count(s.sentiment_score), 0) AS positive_ratio
FROM {{ ref('stg_ohlcv') }} AS o
CROSS JOIN (SELECT arrayJoin([1, 6, 24]) AS window_hours) AS w
LEFT JOIN {{ ref('stg_sentiment') }} AS s
    ON s.symbol = o.symbol
    AND s.timestamp >= o.timestamp - INTERVAL w.window_hours HOUR
    AND s.timestamp <= o.timestamp
GROUP BY symbol, timestamp, window_hours
-- NO `HAVING news_count > 0`: emit a row for EVERY OHLCV bar × window, not only
-- bars that happen to have news in the window. The LEFT JOIN to stg_sentiment
-- already yields news_count=0 / avg_sentiment=0 (neutral) for newsless windows;
-- dropping those rows is what left the downstream exact-timestamp join in
-- fct_training_data unmatched becomes NULL, then fillna(0), so the 7 sentiment features were
-- dead-zero for every row. Dense output makes the join hit every bar: sparse
-- windows carry a real neutral signal (count=0), news-bearing windows carry the
-- true trailing aggregate. FLAML drops any window that stays near-constant.
