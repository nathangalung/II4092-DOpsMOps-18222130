"""
Training data preparation — config-driven feature selection.

Prepares train/validation splits from ClickHouse feature data.
Feature columns are auto-discovered from data or set via FEATURE_COLUMNS env var.
FLAML handles the actual model training; this module only prepares the data.
"""

import logging
import os

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split

logger = logging.getLogger(__name__)

# Columns to exclude from features (metadata, not model inputs).
_default_exclude = "symbol,timestamp,date,hour,data_type,created_at,computed_at"
EXCLUDE_COLS = [
    col.strip()
    for col in os.getenv("EXCLUDE_COLUMNS", _default_exclude).split(",")
    if col.strip()
]

TARGET_COLUMN = os.getenv("TARGET_COLUMN", "target")

# Optional: explicitly list feature columns via env var.
_feature_cols_env = os.getenv("FEATURE_COLUMNS", "")
EXPLICIT_FEATURE_COLS = (
    [col.strip() for col in _feature_cols_env.split(",") if col.strip()]
    if _feature_cols_env
    else []
)


class Trainer:
    """Data preparation for FLAML AutoML — config-driven feature selection."""

    def __init__(self, df: pd.DataFrame) -> None:
        self.df = df
        self.feature_cols: list[str] | None = None

    def _get_feature_columns(self) -> list[str]:
        """Get feature columns.

        Priority:
        1. FEATURE_COLUMNS env var (explicit list)
        2. Auto-discover: all numeric columns minus excluded columns
        """
        if EXPLICIT_FEATURE_COLS:
            feature_cols = [c for c in EXPLICIT_FEATURE_COLS if c in self.df.columns]
            logger.info("Using explicit feature columns: %d", len(feature_cols))
            return feature_cols

        exclude_set = set(EXCLUDE_COLS) | {TARGET_COLUMN}
        feature_cols = [
            col
            for col in self.df.columns
            if col not in exclude_set and pd.api.types.is_numeric_dtype(self.df[col])
        ]

        logger.info("Auto-discovered %d feature columns", len(feature_cols))
        return feature_cols

    def _clean_features(self) -> np.ndarray:
        """Clean feature data: forward fill, replace inf/nan."""
        self.feature_cols = self._get_feature_columns()
        df_clean = self.df[self.feature_cols].copy()
        df_clean = df_clean.ffill().fillna(0)
        df_clean = df_clean.replace([np.inf, -np.inf], 0)
        return df_clean.values

    def prepare_regression_data(self) -> tuple:
        """Prepare data for regression. Uses raw TARGET_COLUMN values."""
        features = self._clean_features()
        targets = self.df[TARGET_COLUMN].values

        mask = ~np.isnan(targets)
        features = features[mask]
        targets = targets[mask]

        return train_test_split(features, targets, test_size=0.2, shuffle=False)

    def prepare_classification_data(self) -> tuple:
        """Prepare data for classification.

        Bins target returns into discrete classes using CLASSIFICATION_THRESHOLD.
        """
        features = self._clean_features()

        threshold = float(os.getenv("CLASSIFICATION_THRESHOLD", "0.01"))
        returns = self.df[TARGET_COLUMN].pct_change().shift(-1)
        labels = np.where(
            returns > threshold,
            0,
            np.where(returns < -threshold, 2, 1),
        )

        mask = ~np.isnan(returns)
        features = features[mask]
        labels = labels[mask]

        return train_test_split(features, labels, test_size=0.2, shuffle=False)
