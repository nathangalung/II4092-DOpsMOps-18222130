"""Tests for training orchestrator."""

from unittest.mock import MagicMock

import numpy as np
import pandas as pd
import pytest

from src.trainer import Trainer


@pytest.fixture
def sample_df() -> pd.DataFrame:
    """Sample dataframe with features."""
    np.random.seed(42)
    n = 200
    df = pd.DataFrame(
        {
            "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
            "symbol": "SYMBOL-A",
            "target": 500 + np.cumsum(np.random.randn(n) * 10),
            "value_a": np.random.randn(n) * 10 + 500,
            "value_b": np.random.randn(n) * 10 + 510,
            "value_c": np.random.randn(n) * 10 + 490,
            "quantity": np.random.randint(1000, 10000, n).astype(float),
            "indicator_a": np.random.randn(n) * 10 + 500,
            "indicator_b": np.random.rand(n) * 100,
            "indicator_c": np.random.randn(n) * 10,
            "supplementary_1h": np.random.randn(n),
            "event_count_1h": np.random.randint(0, 10, n),
        }
    )
    return df


class TestTrainer:
    def test_init(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        assert trainer.df is not None
        assert trainer.sequence_length == 24

    def test_init_custom_sequence(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df, sequence_length=10)
        assert trainer.sequence_length == 10

    def test_get_feature_columns(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        cols = trainer._get_feature_columns()
        assert isinstance(cols, list)
        assert len(cols) > 0
        # Should include available numeric feature columns
        assert "indicator_a" in cols or "indicator_b" in cols

    def test_get_feature_columns_excludes_metadata(
        self, sample_df: pd.DataFrame
    ) -> None:
        trainer = Trainer(sample_df)
        cols = trainer._get_feature_columns()
        assert isinstance(cols, list)
        assert len(cols) > 0
        # Should exclude timestamp and symbol (metadata)
        assert "timestamp" not in cols
        assert "symbol" not in cols

    def test_prepare_lstm_data(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df, sequence_length=10)
        x_train, x_val, y_train, y_val = trainer.prepare_lstm_data()
        assert x_train.ndim == 3  # (samples, sequence, features)
        assert x_train.shape[1] == 10  # sequence_length
        assert len(y_train) == len(x_train)
        assert len(y_val) == len(x_val)

    def test_prepare_classification_data(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        x_train, x_val, y_train, y_val = trainer.prepare_classification_data()
        assert x_train.ndim == 2  # (samples, features)
        assert len(y_train) == len(x_train)
        # Labels should be 0, 1, or 2
        assert set(np.unique(y_train)).issubset({0, 1, 2})

    def test_prepare_regression_data(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        x_train, x_val, y_train, y_val = trainer.prepare_regression_data()
        assert x_train.ndim == 2  # (samples, features)
        assert len(y_train) == len(x_train)
        # Regression targets should be continuous values
        assert y_train.dtype in [np.float64, np.float32]

    def test_handles_nan(self, sample_df: pd.DataFrame) -> None:
        sample_df.loc[0:10, "indicator_b"] = np.nan
        trainer = Trainer(sample_df)
        x_train, _, _, _ = trainer.prepare_lstm_data()
        # Should not contain NaN after preparation
        assert not np.isnan(x_train).any()

    def test_handles_inf(self, sample_df: pd.DataFrame) -> None:
        sample_df.loc[0, "indicator_c"] = np.inf
        trainer = Trainer(sample_df)
        x_train, _, _, _ = trainer.prepare_lstm_data()
        assert not np.isinf(x_train).any()

    def test_train_lstm(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df, sequence_length=5)
        mock_model = MagicMock()
        mock_model.fit.return_value = {"val_loss": 0.01, "val_mae": 0.05}
        trainer.train_lstm(mock_model)
        mock_model.build.assert_called_once()
        mock_model.fit.assert_called_once()

    def test_train_classification(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        mock_model = MagicMock()
        mock_model.fit.return_value = {"accuracy": 0.7, "f1_score": 0.65}
        trainer.train_classification(mock_model)
        mock_model.build.assert_called_once()
        mock_model.fit.assert_called_once()

    def test_train_regression(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        mock_model = MagicMock()
        mock_model.fit.return_value = {"rmse": 0.05, "mae": 0.03, "r2": 0.9}
        trainer.train_regression(mock_model)
        mock_model.build.assert_called_once()
        mock_model.fit.assert_called_once()

    def test_get_feature_importance(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        trainer.feature_cols = ["feat1", "feat2"]
        mock_model = MagicMock()
        mock_model.feature_importances_ = np.array([0.3, 0.7])
        importance = trainer.get_feature_importance(mock_model)
        assert importance == {"feat1": 0.3, "feat2": 0.7}

    def test_get_feature_importance_no_attr(self, sample_df: pd.DataFrame) -> None:
        trainer = Trainer(sample_df)
        mock_model = MagicMock(spec=[])  # No feature_importances_
        importance = trainer.get_feature_importance(mock_model)
        assert importance == {}
