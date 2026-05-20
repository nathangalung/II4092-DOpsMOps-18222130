"""
Temporal feature transformers for batch processing.
Computes time-based features, lag features, and return features.
"""

import numpy as np
import pandas as pd


def compute_time_features(
    df: pd.DataFrame, timestamp_col: str = "timestamp"
) -> pd.DataFrame:
    """
    Compute time-based features from timestamp.

    Args:
        df: DataFrame with timestamp column
        timestamp_col: Name of the timestamp column

    Returns:
        DataFrame with time features added
    """
    result = df.copy()
    ts = pd.to_datetime(df[timestamp_col])

    # Hour of day (0-23)
    result["hour_of_day"] = ts.dt.hour

    # Day of week (0=Monday, 6=Sunday)
    result["day_of_week"] = ts.dt.dayofweek

    # Is weekend
    result["is_weekend"] = (ts.dt.dayofweek >= 5).astype(int)

    # High-activity period flags (configurable via ACTIVE_HOURS_* env vars)
    import os

    active_start = int(os.getenv("ACTIVE_HOURS_START", "9"))
    active_end = int(os.getenv("ACTIVE_HOURS_END", "17"))
    result["is_active_hours"] = (
        (ts.dt.hour >= active_start) & (ts.dt.hour <= active_end)
    ).astype(int)

    # Day of month
    result["day_of_month"] = ts.dt.day

    # Month
    result["month"] = ts.dt.month

    # Cyclical encoding for hour (sin/cos)
    result["hour_sin"] = np.sin(2 * np.pi * ts.dt.hour / 24)
    result["hour_cos"] = np.cos(2 * np.pi * ts.dt.hour / 24)

    # Cyclical encoding for day of week
    result["dow_sin"] = np.sin(2 * np.pi * ts.dt.dayofweek / 7)
    result["dow_cos"] = np.cos(2 * np.pi * ts.dt.dayofweek / 7)

    return result


def compute_lag_features(
    df: pd.DataFrame, columns: list[str], lags: list[int] = None
) -> pd.DataFrame:
    """
    Compute lagged features for specified columns.

    Args:
        df: DataFrame with columns to lag
        columns: List of column names to create lags for
        lags: List of lag periods (in hours)

    Returns:
        DataFrame with lag features added
    """
    if lags is None:
        lags = [1, 6, 12, 24]
    result = df.copy()

    for col in columns:
        if col not in df.columns:
            continue
        for lag in lags:
            result[f"{col}_lag_{lag}h"] = df[col].shift(lag)

    return result


def compute_return_features(
    df: pd.DataFrame, value_col: str = "value", periods: list[int] = None
) -> pd.DataFrame:
    """
    Compute return features over different periods.

    Args:
        df: DataFrame with value column
        value_col: Name of the primary value column
        periods: List of periods to compute returns for

    Returns:
        DataFrame with return features added
    """
    if periods is None:
        periods = [1, 6, 12, 24]
    result = df.copy()

    for period in periods:
        # Simple return
        result[f"return_{period}h"] = df[value_col].pct_change(periods=period)

        # Log return
        result[f"log_return_{period}h"] = np.log(
            df[value_col] / df[value_col].shift(period)
        )

    return result


def compute_target_features(
    df: pd.DataFrame, value_col: str = "value", horizons: list[int] = None
) -> pd.DataFrame:
    """
    Compute target variables (future returns) for training.

    Args:
        df: DataFrame with value column
        value_col: Name of the primary value column
        horizons: List of future horizons to predict

    Returns:
        DataFrame with target features added
    """
    if horizons is None:
        horizons = [1]
    result = df.copy()

    for horizon in horizons:
        # Future return (target for prediction)
        result[f"target_return_{horizon}h"] = (
            df[value_col].pct_change(periods=horizon).shift(-horizon)
        )

        # Future value
        result[f"target_value_{horizon}h"] = df[value_col].shift(-horizon)

        # Direction (for classification: 0=down, 1=up)
        result[f"target_direction_{horizon}h"] = (
            result[f"target_return_{horizon}h"] > 0
        ).astype(int)

    return result
