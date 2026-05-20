"""
Feature engineering job for batch processing.
Reads raw data from ClickHouse, computes features, and writes back.

This is a GENERIC feature engineering runner — all indicator types,
periods, columns, and horizons come from the use-case config.yaml.
"""

import logging
import os
from datetime import UTC, datetime, timedelta

import clickhouse_connect
import pandas as pd

from config import Config
from transformers import (
    compute_dispersion_features,
    compute_lag_features,
    compute_return_features,
    compute_target_features,
    compute_technical_indicators,
    compute_time_features,
)

logger = logging.getLogger(__name__)

DATA_TABLE = os.getenv("DATA_TABLE", "raw_data")
FEATURES_TABLE = os.getenv("FEATURES_TABLE", "features")


class FeatureEngineeringJob:
    """
    Generic batch job for computing features from tabular data.

    This job:
    1. Reads raw data from ClickHouse (configurable table and columns)
    2. Computes indicators, time features, lags (all config-driven)
    3. Writes computed features to ClickHouse (configurable features table)

    All domain-specific settings (which indicators, what periods, which
    columns to lag) come from the use-case's config.yaml — not hardcoded.
    """

    def __init__(self, config: Config) -> None:
        self.config = config
        self.client = None

    def connect(self) -> None:
        """Connect to ClickHouse."""
        self.client = clickhouse_connect.get_client(
            host=self.config.clickhouse_host,
            port=self.config.clickhouse_port,
            database=self.config.clickhouse_database,
        )
        host = self.config.clickhouse_host
        port = self.config.clickhouse_port
        logger.info(f"Connected to ClickHouse at {host}:{port}")

    def run(
        self, start_time: datetime | None = None, end_time: datetime | None = None
    ) -> None:
        """
        Run the feature engineering job.

        Args:
            start_time: Start of time range to process (default: last 24 hours)
            end_time: End of time range to process (default: now)
        """
        if self.client is None:
            self.connect()

        if end_time is None:
            end_time = datetime.now(tz=UTC)
        if start_time is None:
            start_time = end_time - timedelta(hours=24)

        logger.info(f"Processing features from {start_time} to {end_time}")

        for symbol in self.config.symbols:
            try:
                self._process_symbol(symbol, start_time, end_time)
            except Exception as e:
                logger.error(f"Error processing {symbol}: {e}")

    def _process_symbol(
        self, symbol: str, start_time: datetime, end_time: datetime
    ) -> None:
        """Process features for a single symbol."""
        lookback = timedelta(days=7)
        df = self._load_raw_data(symbol, start_time - lookback, end_time)

        if df.empty:
            logger.warning(f"No data found for {symbol}")
            return

        logger.info(f"Loaded {len(df)} records for {symbol}")

        df = self._compute_all_features(df)

        # Strip timezone for pandas datetime64 comparison
        start_naive = start_time.replace(tzinfo=None) if start_time.tzinfo else start_time
        end_naive = end_time.replace(tzinfo=None) if end_time.tzinfo else end_time
        df = df[(df["timestamp"] >= start_naive) & (df["timestamp"] <= end_naive)]

        if df.empty:
            logger.warning(f"No data after filtering for {symbol}")
            return

        df = df.dropna()

        logger.info(f"Writing {len(df)} feature records for {symbol}")
        self._write_features(df, symbol)

    def _load_raw_data(
        self, symbol: str, start_time: datetime, end_time: datetime
    ) -> pd.DataFrame:
        """Load raw data from ClickHouse using configured columns."""
        columns = ["symbol", "timestamp"] + self.config.data_columns
        col_str = ", ".join(columns)

        query = f"""
            SELECT {col_str}
            FROM {DATA_TABLE}
            WHERE symbol = '{symbol}'
              AND timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
              AND timestamp <= '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
            ORDER BY timestamp ASC
        """

        result = self.client.query(query)
        df = pd.DataFrame(result.result_rows, columns=columns)

        if not df.empty:
            df["timestamp"] = pd.to_datetime(df["timestamp"])

        return df

    def _compute_all_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Compute all features — driven entirely by config."""
        # Technical indicators (config specifies which indicators and periods)
        if self.config.technical_indicators:
            df = compute_technical_indicators(df, self.config.technical_indicators)

        # Dispersion features (config specifies window sizes)
        df = compute_dispersion_features(df, windows=self.config.dispersion_windows)

        # Time features (optional)
        if self.config.time_features_enabled:
            df = compute_time_features(df)

        # Lag features (config specifies which columns and periods)
        available_lag_cols = [c for c in self.config.lag_columns if c in df.columns]
        if available_lag_cols:
            df = compute_lag_features(df, available_lag_cols, self.config.lag_periods)

        # Return features (config specifies periods and price column)
        df = compute_return_features(
            df, value_col=self.config.return_column, periods=self.config.return_periods
        )

        # Target features (config specifies horizons and target column)
        df = compute_target_features(
            df,
            value_col=self.config.target_column,
            horizons=self.config.target_horizons,
        )

        return df

    def _write_features(self, df: pd.DataFrame, symbol: str) -> None:
        """Write computed features to ClickHouse."""
        df["computed_at"] = datetime.now(tz=UTC)
        columns = df.columns.tolist()

        self.client.insert(
            table=FEATURES_TABLE,
            data=df.values.tolist(),
            column_names=columns,
        )

    def close(self) -> None:
        """Close ClickHouse connection."""
        if self.client:
            self.client.close()
            self.client = None
