"""Tests for technical indicator transformers."""

from typing import Any

import numpy as np
import pandas as pd
import pytest

from transformers.technical import (
    compute_dispersion_features,
    compute_technical_indicators,
)


@pytest.fixture
def sample_df() -> pd.DataFrame:
    """Sample time-series dataframe with generic value columns."""
    np.random.seed(42)
    n = 100
    base = 100 + np.cumsum(np.random.randn(n) * 2)
    return pd.DataFrame(
        {
            "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
            "value_1": base + np.random.randn(n) * 1,
            "value_2": base + np.abs(np.random.randn(n) * 2),
            "value_3": base - np.abs(np.random.randn(n) * 2),
            "value_4": base,
            "value_5": np.random.randint(1000, 10000, n).astype(float),
        }
    )


@pytest.fixture
def config() -> dict[str, Any]:
    """Technical config."""
    return {
        "moving_averages": {"rolling_mean": [7, 14], "exp_avg": [12, 26]},
        "momentum": {"roc": [10], "zscore": [20]},
        "rolling_stats": {"std": [14], "min": [14], "max": [14]},
    }


class TestComputeTechnicalIndicators:
    def test_returns_dataframe(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert isinstance(result, pd.DataFrame)

    def test_preserves_rows(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert len(result) == len(sample_df)

    def test_creates_rolling_mean(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert "rolling_mean_7" in result.columns
        assert "rolling_mean_14" in result.columns

    def test_creates_rolling_ema(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert "rolling_ema_12" in result.columns
        assert "rolling_ema_26" in result.columns

    def test_creates_roc(self, sample_df: pd.DataFrame, config: dict[str, Any]) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert "roc_10" in result.columns

    def test_creates_zscore(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert "zscore_20" in result.columns

    def test_creates_rolling_stats(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        assert "rolling_std_14" in result.columns
        assert "rolling_min_14" in result.columns
        assert "rolling_max_14" in result.columns

    def test_rolling_bounds(
        self, sample_df: pd.DataFrame, config: dict[str, Any]
    ) -> None:
        result = compute_technical_indicators(sample_df, config)
        valid = result.dropna(subset=["rolling_min_14", "rolling_max_14"])
        assert (valid["rolling_max_14"] >= valid["rolling_min_14"]).all()

    def test_empty_config(self, sample_df: pd.DataFrame) -> None:
        result = compute_technical_indicators(sample_df, {})
        assert isinstance(result, pd.DataFrame)
        assert "rolling_mean_20" in result.columns  # Default rolling mean


class TestComputeDispersionFeatures:
    def test_returns_dataframe(self, sample_df: pd.DataFrame) -> None:
        result = compute_dispersion_features(sample_df)
        assert isinstance(result, pd.DataFrame)

    def test_default_windows(self, sample_df: pd.DataFrame) -> None:
        result = compute_dispersion_features(sample_df)
        # window=1 is degenerate (rolling(1).std() ≡ NaN) and is now skipped —
        # see test_skips_degenerate_window. Only the real window survives.
        assert "dispersion_1" not in result.columns
        assert "dispersion_24" in result.columns

    def test_skips_degenerate_window(self, sample_df: pd.DataFrame) -> None:
        """Regression #500: window=1 → rolling(1).std() is an all-NaN column.
        A blanket df.dropna() downstream then wiped every row (green-but-empty
        insert). Degenerate windows must produce NO column at all."""
        result = compute_dispersion_features(sample_df, windows=[1, 24])
        assert "dispersion_1" not in result.columns
        assert "range_1" not in result.columns
        # The real window is unaffected and is not all-NaN.
        assert "dispersion_24" in result.columns
        assert result["dispersion_24"].notna().any()

    def test_custom_windows(self, sample_df: pd.DataFrame) -> None:
        result = compute_dispersion_features(sample_df, windows=[6, 12])
        assert "dispersion_6" in result.columns
        assert "dispersion_12" in result.columns

    def test_range_features(self, sample_df: pd.DataFrame) -> None:
        result = compute_dispersion_features(sample_df, windows=[1, 24])
        assert "range_24" in result.columns
        assert "range_1" not in result.columns  # window must be > 1

    def test_dispersion_positive(self, sample_df: pd.DataFrame) -> None:
        result = compute_dispersion_features(sample_df)
        disp = result["dispersion_24"].dropna()
        assert (disp >= 0).all()
