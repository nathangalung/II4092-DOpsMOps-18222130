"""
Generic statistical transformers for batch processing.
Computes rolling statistics, dispersion, and windowed aggregations.
No domain-specific dependencies — works for any numeric time series.

Use-cases that need domain-specific indicators (e.g., financial technical analysis)
should add their own transformer module and register it in their config.
"""

import os

import numpy as np
import pandas as pd


def compute_technical_indicators(df: pd.DataFrame, config: dict) -> pd.DataFrame:
    """
    Compute generic statistical indicators based on configuration.

    Args:
        df: DataFrame with numeric columns
        config: Indicator configuration from config.yaml

    Returns:
        DataFrame with original columns plus computed indicators
    """
    result = df.copy()

    # Determine the primary value column (configurable)
    value_col = os.getenv("PRIMARY_VALUE_COLUMN", config.get("value_column", "value"))
    if value_col not in df.columns:
        # Fall back to first numeric column
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        if len(numeric_cols) == 0:
            return result
        value_col = numeric_cols[0]

    # Rolling Means
    ma_config = config.get("moving_averages", {})
    for period in ma_config.get("rolling_mean", [20, 50]):
        result[f"rolling_mean_{period}"] = df[value_col].rolling(window=period).mean()

    for period in ma_config.get("exp_avg", [12, 26]):
        result[f"rolling_ema_{period}"] = df[value_col].ewm(span=period).mean()

    # Rolling Statistics
    stats_config = config.get("rolling_stats", {})
    for period in stats_config.get("std", []):
        result[f"rolling_std_{period}"] = df[value_col].rolling(window=period).std()
    for period in stats_config.get("min", []):
        result[f"rolling_min_{period}"] = df[value_col].rolling(window=period).min()
    for period in stats_config.get("max", []):
        result[f"rolling_max_{period}"] = df[value_col].rolling(window=period).max()
    for period in stats_config.get("median", []):
        result[f"rolling_median_{period}"] = (
            df[value_col].rolling(window=period).median()
        )

    # Momentum (rate of change)
    momentum_config = config.get("momentum", {})
    for period in momentum_config.get("roc", []):
        result[f"roc_{period}"] = df[value_col].pct_change(periods=period) * 100

    # Z-Score (how many std deviations from rolling mean)
    for period in momentum_config.get("zscore", []):
        rolling_mean = df[value_col].rolling(window=period).mean()
        rolling_std = df[value_col].rolling(window=period).std()
        result[f"zscore_{period}"] = (
            df[value_col] - rolling_mean
        ) / rolling_std.replace(0, np.nan)

    # Percentile rank within rolling window
    for period in stats_config.get("percentile_rank", []):
        result[f"pctrank_{period}"] = (
            df[value_col]
            .rolling(window=period)
            .apply(lambda x: pd.Series(x).rank(pct=True).iloc[-1], raw=False)
        )

    return result


def compute_dispersion_features(
    df: pd.DataFrame, windows: list[int] = None
) -> pd.DataFrame:
    """
    Compute dispersion-based features for any numeric time series.

    Args:
        df: DataFrame with a primary value column
        windows: List of window sizes for dispersion calculation

    Returns:
        DataFrame with dispersion features added
    """
    if windows is None:
        windows = [1, 24]
    result = df.copy()

    value_col = os.getenv("PRIMARY_VALUE_COLUMN", "value")
    if value_col not in df.columns:
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        if len(numeric_cols) == 0:
            return result
        value_col = numeric_cols[0]

    for window in windows:
        # Rolling standard deviation of returns
        returns = df[value_col].pct_change()
        result[f"dispersion_{window}"] = returns.rolling(window=window).std()

        # Rolling range / value
        if window > 1:
            rolling_max = df[value_col].rolling(window=window).max()
            rolling_min = df[value_col].rolling(window=window).min()
            result[f"range_{window}"] = (rolling_max - rolling_min) / df[
                value_col
            ].replace(0, np.nan)

    return result
