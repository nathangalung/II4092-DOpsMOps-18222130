"""
Batch sentiment aggregation job (domain-agnostic).
Reads raw sentiment data from ClickHouse, computes windowed features,
and writes aggregated sentiment features.

Domain-specific extensions (e.g., specialized index sync) are provided
by use-case overlays that subclass SentimentAggregationJob.
"""

import logging
import os
from datetime import UTC, datetime, timedelta

import clickhouse_connect
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

SENTIMENT_RAW_TABLE = os.getenv(
    "SENTIMENT_RAW_TABLE", "sentiment_raw"
)
SENTIMENT_FEATURES_TABLE = os.getenv(
    "SENTIMENT_FEATURES_TABLE", "sentiment_features"
)
WINDOW_HOURS = [1, 6, 24]

CLICKHOUSE_HOST = os.getenv(
    "CLICKHOUSE_HOST", "clickhouse-platform.storage.svc.cluster.local"
)
CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
CLICKHOUSE_DB = os.getenv("CLICKHOUSE_DB", "features")
SYMBOLS = [
    s.strip()
    for s in os.getenv("VALID_SYMBOLS", "SAMPLE-001").split(",")
    if s.strip()
]


class SentimentAggregationJob:
    """Computes windowed sentiment features from raw sentiment data.

    Override `run_domain_tasks()` in a subclass to add domain-specific
    post-processing (e.g., syncing external indices).
    """

    def __init__(self) -> None:
        self.client = None

    def connect(self) -> None:
        self.client = clickhouse_connect.get_client(
            host=CLICKHOUSE_HOST,
            port=CLICKHOUSE_PORT,
            database=CLICKHOUSE_DB,
        )
        logger.info(
            f"Connected to ClickHouse at {CLICKHOUSE_HOST}:{CLICKHOUSE_PORT}"
        )

    def run(self) -> None:
        if self.client is None:
            self.connect()

        now = datetime.now(tz=UTC)
        lookback = timedelta(hours=max(WINDOW_HOURS) + 1)
        start = now - lookback

        for symbol in SYMBOLS:
            try:
                self._process_symbol(symbol, start, now)
            except Exception as e:
                logger.error(
                    f"Error processing sentiment for {symbol}: {e}"
                )

        # Hook for domain-specific tasks (overridden by use-case)
        self.run_domain_tasks()

    def run_domain_tasks(self) -> None:
        """Override in subclass for domain-specific post-processing."""

    def _process_symbol(
        self, symbol: str, start: datetime, end: datetime
    ) -> None:
        df = self._load_sentiment(symbol, start, end)
        if df.empty:
            logger.warning(f"No sentiment data for {symbol}")
            return

        logger.info(f"Loaded {len(df)} sentiment records for {symbol}")

        end_naive = end.replace(tzinfo=None)
        results = []
        for window_h in WINDOW_HOURS:
            window_start = end_naive - timedelta(hours=window_h)
            window_df = df[df["timestamp"] >= window_start]

            if window_df.empty:
                continue

            scores = window_df["sentiment_score"].values
            news_count = len(window_df)
            avg_sentiment = float(np.mean(scores))
            sentiment_std = (
                float(np.std(scores)) if news_count > 1 else 0.0
            )
            positive_ratio = float(np.sum(scores > 0.6) / news_count)

            mid = len(scores) // 2
            if mid > 0:
                recent_avg = float(np.mean(scores[mid:]))
                older_avg = float(np.mean(scores[:mid]))
                sentiment_momentum = recent_avg - older_avg
            else:
                sentiment_momentum = 0.0

            results.append({
                "symbol": symbol,
                "timestamp": end,
                "window_hours": window_h,
                "news_count": news_count,
                "avg_sentiment": avg_sentiment,
                "sentiment_std": sentiment_std,
                "positive_ratio": positive_ratio,
                "sentiment_momentum": sentiment_momentum,
            })

        if results:
            self._write_features(results)
            logger.info(
                f"Wrote {len(results)} sentiment feature rows "
                f"for {symbol}"
            )

    def _load_sentiment(
        self, symbol: str, start: datetime, end: datetime
    ) -> pd.DataFrame:
        query = f"""
            SELECT symbol, timestamp, sentiment_score,
                   sentiment_label, source
            FROM {SENTIMENT_RAW_TABLE}
            WHERE symbol = '{symbol}'
              AND timestamp >= '{start.strftime("%Y-%m-%d %H:%M:%S")}'
              AND timestamp <= '{end.strftime("%Y-%m-%d %H:%M:%S")}'
            ORDER BY timestamp ASC
        """
        result = self.client.query(query)
        columns = [
            "symbol", "timestamp", "sentiment_score",
            "sentiment_label", "source",
        ]
        df = pd.DataFrame(result.result_rows, columns=columns)
        if not df.empty:
            df["timestamp"] = pd.to_datetime(df["timestamp"])
        return df

    def _write_features(self, results: list[dict]) -> None:
        columns = [
            "symbol",
            "timestamp",
            "window_hours",
            "news_count",
            "avg_sentiment",
            "sentiment_std",
            "positive_ratio",
            "sentiment_momentum",
        ]
        data = [[row[c] for c in columns] for row in results]
        self.client.insert(
            table=SENTIMENT_FEATURES_TABLE,
            data=data,
            column_names=columns,
        )

    def close(self) -> None:
        if self.client:
            self.client.close()
            self.client = None
