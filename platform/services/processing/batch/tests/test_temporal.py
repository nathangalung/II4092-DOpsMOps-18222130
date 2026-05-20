"""Tests for temporal feature transformers."""

import numpy as np
import pandas as pd
import pytest

from transformers.temporal import (
    compute_lag_features,
    compute_return_features,
    compute_target_features,
    compute_time_features,
)


@pytest.fixture
def df() -> pd.DataFrame:
    """Sample dataframe with timestamp and value."""
    return pd.DataFrame(
        {
            "timestamp": pd.date_range("2024-01-01", periods=50, freq="1h"),
            "value": np.linspace(100, 150, 50),
            "value_2": np.random.randint(1000, 5000, 50).astype(float),
        }
    )


class TestComputeTimeFeatures:
    def test_returns_dataframe(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert isinstance(result, pd.DataFrame)

    def test_hour_of_day(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert "hour_of_day" in result.columns
        assert result["hour_of_day"].between(0, 23).all()

    def test_day_of_week(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert "day_of_week" in result.columns
        assert result["day_of_week"].between(0, 6).all()

    def test_is_weekend(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert "is_weekend" in result.columns
        assert result["is_weekend"].isin([0, 1]).all()

    def test_active_hours(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert "is_active_hours" in result.columns
        assert result["is_active_hours"].isin([0, 1]).all()

    def test_cyclical_encoding(self, df: pd.DataFrame) -> None:
        result = compute_time_features(df)
        assert "hour_sin" in result.columns
        assert "hour_cos" in result.columns
        assert "dow_sin" in result.columns
        assert "dow_cos" in result.columns
        # Sin/cos should be bounded [-1, 1]
        assert result["hour_sin"].between(-1, 1).all()
        assert result["hour_cos"].between(-1, 1).all()


class TestComputeLagFeatures:
    def test_returns_dataframe(self, df: pd.DataFrame) -> None:
        result = compute_lag_features(df, ["value"])
        assert isinstance(result, pd.DataFrame)

    def test_creates_lags(self, df: pd.DataFrame) -> None:
        result = compute_lag_features(df, ["value"], lags=[1, 6])
        assert "value_lag_1h" in result.columns
        assert "value_lag_6h" in result.columns

    def test_lag_values(self, df: pd.DataFrame) -> None:
        result = compute_lag_features(df, ["value"], lags=[1])
        # First row should be NaN, second row should equal first value
        assert pd.isna(result["value_lag_1h"].iloc[0])
        assert result["value_lag_1h"].iloc[1] == df["value"].iloc[0]

    def test_missing_column_ignored(self, df: pd.DataFrame) -> None:
        result = compute_lag_features(df, ["nonexistent"], lags=[1])
        assert "nonexistent_lag_1h" not in result.columns


class TestComputeReturnFeatures:
    def test_returns_dataframe(self, df: pd.DataFrame) -> None:
        result = compute_return_features(df)
        assert isinstance(result, pd.DataFrame)

    def test_creates_returns(self, df: pd.DataFrame) -> None:
        result = compute_return_features(df, periods=[1, 6])
        assert "return_1h" in result.columns
        assert "return_6h" in result.columns
        assert "log_return_1h" in result.columns
        assert "log_return_6h" in result.columns

    def test_return_calculation(self, df: pd.DataFrame) -> None:
        result = compute_return_features(df, periods=[1])
        # Simple return = (current - previous) / previous
        expected = df["value"].pct_change(periods=1)
        pd.testing.assert_series_equal(result["return_1h"], expected, check_names=False)


class TestComputeTargetFeatures:
    def test_returns_dataframe(self, df: pd.DataFrame) -> None:
        result = compute_target_features(df)
        assert isinstance(result, pd.DataFrame)

    def test_creates_targets(self, df: pd.DataFrame) -> None:
        result = compute_target_features(df, horizons=[1])
        assert "target_return_1h" in result.columns
        assert "target_value_1h" in result.columns
        assert "target_direction_1h" in result.columns

    def test_direction_binary(self, df: pd.DataFrame) -> None:
        result = compute_target_features(df, horizons=[1])
        assert result["target_direction_1h"].dropna().isin([0, 1]).all()

    def test_future_shift(self, df: pd.DataFrame) -> None:
        result = compute_target_features(df, horizons=[1])
        # Last row should be NaN (no future data)
        assert pd.isna(result["target_value_1h"].iloc[-1])
        # Second to last should equal last value
        assert result["target_value_1h"].iloc[-2] == df["value"].iloc[-1]
