-- Data quality gate: all OHLCV prices must be positive
SELECT count(*) AS violations
FROM {{ ref('stg_ohlcv') }}
WHERE close < 0 OR open < 0 OR high < 0 OR low < 0
HAVING count(*) > 0
