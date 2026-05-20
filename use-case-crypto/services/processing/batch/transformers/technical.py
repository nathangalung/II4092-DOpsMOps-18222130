"""
Crypto-specific technical analysis transformers.
Drop-in replacement for the generic transformers/technical.py — same function signatures,
but adds financial indicators (MACD, Bollinger, ATR, OBV, MFI, VWAP) via the `ta` library.

This module is overlaid INTO the Docker image during build (replaces the generic version).
The `ta` dependency is added via requirements-extra.txt (also overlaid during build).
"""

import os

import numpy as np
import pandas as pd
import ta


def compute_technical_indicators(df: pd.DataFrame, config: dict) -> pd.DataFrame:
    """
    Compute technical indicators — generic stats + crypto-specific financial TA.

    Same function signature as the generic version so it works as a drop-in
    replacement. Adds MACD, Bollinger Bands, ATR, OBV, MFI, VWAP when OHLCV columns
    are present. Falls back to generic rolling stats otherwise.

    Args:
        df: DataFrame with numeric columns (OHLCV for full indicators)
        config: Indicator configuration from config.yaml

    Returns:
        DataFrame with original columns plus computed indicators
    """
    result = df.copy()

    # Determine the primary value column (configurable)
    value_col = os.getenv("PRIMARY_VALUE_COLUMN", config.get("value_column", "close"))
    if value_col not in df.columns:
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        if len(numeric_cols) == 0:
            return result
        value_col = numeric_cols[0]

    has_ohlcv = all(c in df.columns for c in ["open", "high", "low", "close", "volume"])

    # ── Generic rolling statistics ──

    ma_config = config.get("moving_averages", {})
    for period in ma_config.get("sma", [20, 50]):
        result[f"sma_{period}"] = df[value_col].rolling(window=period).mean()

    for period in ma_config.get("ema", [12, 26]):
        result[f"ema_{period}"] = df[value_col].ewm(span=period).mean()

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

    momentum_config = config.get("momentum", {})
    for period in momentum_config.get("roc", []):
        result[f"roc_{period}"] = df[value_col].pct_change(periods=period) * 100

    for period in momentum_config.get("zscore", []):
        rolling_mean = df[value_col].rolling(window=period).mean()
        rolling_std = df[value_col].rolling(window=period).std()
        result[f"zscore_{period}"] = (
            df[value_col] - rolling_mean
        ) / rolling_std.replace(0, np.nan)

    for period in stats_config.get("percentile_rank", []):
        result[f"pctrank_{period}"] = (
            df[value_col]
            .rolling(window=period)
            .apply(lambda x: pd.Series(x).rank(pct=True).iloc[-1], raw=False)
        )

    # ── Crypto-specific financial indicators (requires OHLCV) ──

    if not has_ohlcv:
        return result

    # RSI via ta library (more accurate than simple rolling)
    for period in momentum_config.get("rsi", [7, 14]):
        result[f"rsi_{period}"] = ta.momentum.rsi(df["close"], window=period)

    # MACD
    macd_config = momentum_config.get("macd", {"fast": 12, "slow": 26, "signal": 9})
    macd = ta.trend.MACD(
        df["close"],
        window_slow=macd_config.get("slow", 26),
        window_fast=macd_config.get("fast", 12),
        window_sign=macd_config.get("signal", 9),
    )
    result["macd"] = macd.macd()
    result["macd_signal"] = macd.macd_signal()

    # Bollinger Bands
    vol_config = config.get("volatility", {})
    bb_config = vol_config.get("bollinger", {"period": 20, "std": 2})
    bb = ta.volatility.BollingerBands(
        df["close"],
        window=bb_config.get("period", 20),
        window_dev=bb_config.get("std", 2),
    )
    result["bb_upper"] = bb.bollinger_hband()
    result["bb_lower"] = bb.bollinger_lband()
    result["bb_width"] = bb.bollinger_wband()

    # Stochastic Oscillator
    stoch_config = momentum_config.get("stochastic", {"k": 14, "d": 3})
    stoch = ta.momentum.StochasticOscillator(
        df["high"],
        df["low"],
        df["close"],
        window=stoch_config.get("k", 14),
        smooth_window=stoch_config.get("d", 3),
    )
    result["stoch_k"] = stoch.stoch()
    result["stoch_d"] = stoch.stoch_signal()

    # Williams %R
    wr_period = momentum_config.get("williams_r", 14)
    result["williams_r"] = ta.momentum.williams_r(
        df["high"], df["low"], df["close"], lbp=wr_period
    )

    # Rate of Change (fixed 10-period for ClickHouse schema)
    result["roc_10"] = df["close"].pct_change(periods=10) * 100

    # ADX (Average Directional Index)
    adx_period = momentum_config.get("adx", 14)
    result["adx"] = ta.trend.adx(df["high"], df["low"], df["close"], window=adx_period)

    # Returns
    result["return_1h"] = df["close"].pct_change(periods=1)
    result["return_24h"] = df["close"].pct_change(periods=24)

    # Volatility (24h rolling std of returns)
    result["volatility_24h"] = df["close"].pct_change().rolling(window=24).std()

    # ATR
    atr_period = vol_config.get("atr", 14)
    result[f"atr_{atr_period}"] = ta.volatility.average_true_range(
        df["high"], df["low"], df["close"], window=atr_period
    )

    # Volume indicators
    volume_config = config.get("volume", {})
    if volume_config.get("obv", True):
        result["obv"] = ta.volume.on_balance_volume(df["close"], df["volume"])

    mfi_period = volume_config.get("mfi", 14)
    result[f"mfi_{mfi_period}"] = ta.volume.money_flow_index(
        df["high"], df["low"], df["close"], df["volume"], window=mfi_period
    )

    # VWAP
    result["vwap"] = (
        df["volume"] * (df["high"] + df["low"] + df["close"]) / 3
    ).cumsum() / df["volume"].cumsum()

    return result


def compute_volatility_features(
    df: pd.DataFrame, windows: list[int] | None = None
) -> pd.DataFrame:
    """
    Compute volatility features — generic + crypto OHLCV-based.

    Same signature as the generic version.

    Args:
        df: DataFrame with value column (and optionally OHLCV)
        windows: List of window sizes for volatility calculation

    Returns:
        DataFrame with volatility features added
    """
    if windows is None:
        windows = [1, 24]
    result = df.copy()

    value_col = os.getenv("PRIMARY_VALUE_COLUMN", "close")
    if value_col not in df.columns:
        numeric_cols = df.select_dtypes(include=[np.number]).columns
        if len(numeric_cols) == 0:
            return result
        value_col = numeric_cols[0]

    has_ohlcv = all(c in df.columns for c in ["high", "low", "close"])

    for window in windows:
        returns = df[value_col].pct_change()
        result[f"volatility_{window}"] = returns.rolling(window=window).std()

        if window > 1:
            if has_ohlcv:
                # Use high/low range for OHLCV data (more accurate)
                result[f"range_{window}"] = (
                    df["high"].rolling(window=window).max()
                    - df["low"].rolling(window=window).min()
                ) / df["close"]
            else:
                rolling_max = df[value_col].rolling(window=window).max()
                rolling_min = df[value_col].rolling(window=window).min()
                result[f"range_{window}"] = (rolling_max - rolling_min) / df[
                    value_col
                ].replace(0, np.nan)

    return result
