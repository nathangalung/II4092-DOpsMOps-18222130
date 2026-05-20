"""
Generic outlier detection job.
Columns to check and table names are configurable via environment variables.
"""

import logging
import os
from datetime import UTC, datetime, timedelta
from typing import Any

import clickhouse_connect
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


class OutlierDetector:
    """Detects outliers in numeric data using z-score method."""

    def __init__(self, std_threshold: float = 3.0) -> None:
        """Initialize detector."""
        self.std_threshold = std_threshold
        self.client = self._get_client()

    def _get_client(self) -> Any:
        """Get ClickHouse client."""
        return clickhouse_connect.get_client(
            host=os.getenv("CLICKHOUSE_HOST", "clickhouse"),
            port=int(os.getenv("CLICKHOUSE_PORT", "8123")),
            database=os.getenv("CLICKHOUSE_DB", "features"),
            username=os.getenv("CLICKHOUSE_USER", "default"),
            password=os.getenv("CLICKHOUSE_PASSWORD", ""),
        )

    def run(self) -> None:
        """Run outlier detection."""
        try:
            end_time = datetime.now(tz=UTC).replace(tzinfo=None)
            start_time = end_time - timedelta(hours=24)

            data_table = os.getenv("DATA_TABLE", "raw_data")
            data_columns = os.getenv("DATA_COLUMNS", "symbol,timestamp")
            entity_column = os.getenv("ENTITY_COLUMN", "symbol")

            query = f"""
                SELECT {data_columns}
                FROM {data_table}
                WHERE timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
                  AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
                ORDER BY {entity_column}, timestamp
            """

            result = self.client.query(query)
            if not result.result_rows:
                logger.info("No data to analyze")
                return

            col_names = [c.strip() for c in data_columns.split(",")]
            df = pd.DataFrame(result.result_rows, columns=col_names)

            # Columns to check for outliers — configurable via env
            outlier_columns = [
                c.strip()
                for c in os.getenv("OUTLIER_COLUMNS", "").split(",")
                if c.strip()
            ]
            if not outlier_columns:
                # Auto-detect numeric columns (exclude entity + timestamp)
                exclude = {entity_column, "timestamp"}
                outlier_columns = [
                    c
                    for c in df.columns
                    if c not in exclude and pd.api.types.is_numeric_dtype(df[c])
                ]

            outliers = self._detect_outliers(df, entity_column, outlier_columns)

            if not outliers.empty:
                logger.warning(f"Found {len(outliers)} outliers")
                self._store_outliers(outliers)
            else:
                logger.info("No outliers detected")

        except Exception as e:
            logger.error(f"Outlier detection failed: {e}")
            raise

    def _detect_outliers(
        self,
        df: pd.DataFrame,
        entity_column: str,
        check_columns: list[str],
    ) -> pd.DataFrame:
        """Detect outliers using z-score method on configured columns."""
        outliers = []

        for entity in df[entity_column].unique():
            entity_df = df[df[entity_column] == entity].copy()

            for col in check_columns:
                if col not in entity_df.columns:
                    continue

                mean = entity_df[col].mean()
                std = entity_df[col].std()

                if std > 0:
                    z_scores = np.abs((entity_df[col] - mean) / std)
                    outlier_mask = z_scores > self.std_threshold

                    for _, row in entity_df[outlier_mask].iterrows():
                        outliers.append(
                            {
                                "symbol": entity,
                                "timestamp": row["timestamp"],
                                "column_name": col,
                                "value": row[col],
                                "z_score": z_scores[row.name],
                                "detected_at": datetime.now(tz=UTC).replace(
                                    tzinfo=None
                                ),
                            }
                        )

        return pd.DataFrame(outliers)

    def _store_outliers(self, outliers: pd.DataFrame) -> None:
        """Store outliers to ClickHouse."""
        try:
            self.client.insert(
                "quality_outliers",
                outliers.values.tolist(),
                column_names=list(outliers.columns),
            )
            logger.info(f"Stored {len(outliers)} outliers")
        except Exception as e:
            logger.error(f"Failed to store outliers: {e}")
