-- Data quality gate: no timestamps in the future (+ 1 hour tolerance)
SELECT count(*) AS violations
FROM {{ ref('stg_ohlcv') }}
WHERE timestamp > now() + INTERVAL 1 HOUR
HAVING count(*) > 0
