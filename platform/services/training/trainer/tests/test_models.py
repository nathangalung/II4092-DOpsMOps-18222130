"""Tests for LSTM and XGBoost models."""

from collections.abc import Generator
from unittest.mock import MagicMock, patch

import numpy as np
import pytest


class TestLSTMModel:
    """Tests for LSTMModel class."""

    @pytest.fixture
    def lstm_model(self) -> Generator:
        """Create LSTM model instance."""
        with (
            patch("src.models.lstm.Sequential"),
            patch("src.models.lstm.LSTM"),
            patch("src.models.lstm.Dense"),
            patch("src.models.lstm.Dropout"),
            patch("src.models.lstm.Input"),
            patch("src.models.lstm.Adam"),
        ):
            from src.models.lstm import LSTMModel

            return LSTMModel(sequence_length=24, units=[64, 32])

    def test_init_default_params(self) -> None:
        """Test default initialization."""
        with patch("src.models.lstm.Sequential"):
            from src.models.lstm import LSTMModel

            model = LSTMModel()
            assert model.sequence_length == 24
            assert model.units == [64, 32]
            assert model.model is None
            assert model.feature_names is None

    def test_init_custom_params(self) -> None:
        """Test custom initialization."""
        with patch("src.models.lstm.Sequential"):
            from src.models.lstm import LSTMModel

            model = LSTMModel(sequence_length=48, units=[128, 64, 32])
            assert model.sequence_length == 48
            assert model.units == [128, 64, 32]

    def test_build_creates_model(self, lstm_model: MagicMock) -> None:
        """Test build creates Sequential model."""
        result = lstm_model.build(n_features=10)
        assert result is lstm_model  # Returns self for chaining
        assert lstm_model.model is not None

    def test_build_compiles_model(self) -> None:
        """Test build compiles model with correct optimizer."""
        with (
            patch("src.models.lstm.Sequential") as mock_seq,
            patch("src.models.lstm.LSTM"),
            patch("src.models.lstm.Dense"),
            patch("src.models.lstm.Dropout"),
            patch("src.models.lstm.Input"),
            patch("src.models.lstm.Adam") as mock_adam,
        ):
            from src.models.lstm import LSTMModel

            mock_model = MagicMock()
            mock_seq.return_value = mock_model

            model = LSTMModel()
            model.build(n_features=10)

            mock_adam.assert_called_once_with(learning_rate=0.001)
            mock_model.compile.assert_called_once()

    def test_fit_trains_model(self) -> None:
        """Test fit trains and returns metrics."""
        with (
            patch("src.models.lstm.Sequential") as mock_seq,
            patch("src.models.lstm.LSTM"),
            patch("src.models.lstm.Dense"),
            patch("src.models.lstm.Dropout"),
            patch("src.models.lstm.Input"),
            patch("src.models.lstm.Adam"),
            patch("src.models.lstm.EarlyStopping"),
        ):
            from src.models.lstm import LSTMModel

            mock_model = MagicMock()
            mock_model.fit.return_value = MagicMock(history={"loss": [0.5, 0.3, 0.2]})
            mock_model.evaluate.return_value = (0.1, 0.05)
            mock_seq.return_value = mock_model

            model = LSTMModel(sequence_length=10)
            model.build(n_features=5)

            x_train = np.random.randn(100, 10, 5).astype(np.float32)
            y_train = np.random.randn(100).astype(np.float32)
            x_val = np.random.randn(20, 10, 5).astype(np.float32)
            y_val = np.random.randn(20).astype(np.float32)

            result = model.fit(x_train, y_train, x_val, y_val)

            assert "val_loss" in result
            assert "val_mae" in result
            assert "epochs_trained" in result
            assert result["epochs_trained"] == 3

    def test_fit_uses_early_stopping(self) -> None:
        """Test fit uses early stopping callback."""
        with (
            patch("src.models.lstm.Sequential") as mock_seq,
            patch("src.models.lstm.LSTM"),
            patch("src.models.lstm.Dense"),
            patch("src.models.lstm.Dropout"),
            patch("src.models.lstm.Input"),
            patch("src.models.lstm.Adam"),
            patch("src.models.lstm.EarlyStopping") as mock_es,
        ):
            from src.models.lstm import LSTMModel

            mock_model = MagicMock()
            mock_model.fit.return_value = MagicMock(history={"loss": [0.1]})
            mock_model.evaluate.return_value = (0.1, 0.05)
            mock_seq.return_value = mock_model

            model = LSTMModel(sequence_length=10)
            model.build(n_features=5)

            x = np.random.randn(50, 10, 5).astype(np.float32)
            y = np.random.randn(50).astype(np.float32)
            model.fit(x, y, x, y)

            mock_es.assert_called_once_with(patience=5, restore_best_weights=True)

    def test_predict_returns_array(self) -> None:
        """Test predict returns numpy array."""
        with (
            patch("src.models.lstm.Sequential") as mock_seq,
            patch("src.models.lstm.LSTM"),
            patch("src.models.lstm.Dense"),
            patch("src.models.lstm.Dropout"),
            patch("src.models.lstm.Input"),
            patch("src.models.lstm.Adam"),
        ):
            from src.models.lstm import LSTMModel

            mock_model = MagicMock()
            mock_model.predict.return_value = np.array([[100.0], [102.0]])
            mock_seq.return_value = mock_model

            model = LSTMModel(sequence_length=10)
            model.build(n_features=5)

            x = np.random.randn(2, 10, 5).astype(np.float32)
            result = model.predict(x)

            assert isinstance(result, np.ndarray)
            assert result.shape == (2, 1)


class TestXGBoostModel:
    """Tests for XGBoostModel class."""

    @pytest.fixture
    def xgb_model(self) -> Generator:
        """Create XGBoost model instance."""
        with patch("src.models.xgboost_model.xgb"):
            from src.models.xgboost_model import XGBoostModel

            return XGBoostModel(max_depth=6, n_estimators=100)

    def test_init_default_params(self) -> None:
        """Test default initialization."""
        with patch("src.models.xgboost_model.xgb"):
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel()
            assert model.params["max_depth"] == 6
            assert model.params["n_estimators"] == 100
            assert model.params["learning_rate"] == 0.1
            assert model.params["objective"] == "multi:softmax"
            assert model.params["num_class"] == 3

    def test_init_custom_params(self) -> None:
        """Test custom initialization."""
        with patch("src.models.xgboost_model.xgb"):
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel(max_depth=10, n_estimators=200, learning_rate=0.05)
            assert model.params["max_depth"] == 10
            assert model.params["n_estimators"] == 200
            assert model.params["learning_rate"] == 0.05

    def test_build_creates_classifier(self) -> None:
        """Test build creates XGBClassifier."""
        with patch("src.models.xgboost_model.xgb") as mock_xgb:
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel()
            result = model.build(feature_names=["f1", "f2"])

            assert result is model
            assert model.feature_names == ["f1", "f2"]
            mock_xgb.XGBClassifier.assert_called_once()

    def test_fit_trains_and_evaluates(self) -> None:
        """Test fit trains model and returns metrics."""
        with (
            patch("src.models.xgboost_model.xgb") as mock_xgb,
            patch("src.models.xgboost_model.accuracy_score") as mock_acc,
            patch("src.models.xgboost_model.f1_score") as mock_f1,
            patch("src.models.xgboost_model.precision_score") as mock_prec,
            patch("src.models.xgboost_model.recall_score") as mock_rec,
        ):
            from src.models.xgboost_model import XGBoostModel

            mock_classifier = MagicMock()
            mock_classifier.predict.return_value = np.array([0, 1, 2])
            mock_xgb.XGBClassifier.return_value = mock_classifier

            mock_acc.return_value = 0.85
            mock_f1.return_value = 0.80
            mock_prec.return_value = 0.82
            mock_rec.return_value = 0.78

            model = XGBoostModel()
            model.build()

            x_train = np.random.randn(100, 10)
            y_train = np.random.randint(0, 3, 100)
            x_val = np.random.randn(20, 10)
            y_val = np.random.randint(0, 3, 20)

            result = model.fit(x_train, y_train, x_val, y_val)

            assert result["accuracy"] == 0.85
            assert result["f1_score"] == 0.80
            assert result["precision"] == 0.82
            assert result["recall"] == 0.78

    def test_predict_returns_classes(self) -> None:
        """Test predict returns class labels."""
        with patch("src.models.xgboost_model.xgb") as mock_xgb:
            from src.models.xgboost_model import XGBoostModel

            mock_classifier = MagicMock()
            mock_classifier.predict.return_value = np.array([0, 1, 2, 1, 0])
            mock_xgb.XGBClassifier.return_value = mock_classifier

            model = XGBoostModel()
            model.build()

            x = np.random.randn(5, 10)
            result = model.predict(x)

            assert isinstance(result, np.ndarray)
            assert len(result) == 5
            assert set(result).issubset({0, 1, 2})

    def test_predict_proba_returns_probabilities(self) -> None:
        """Test predict_proba returns probability distributions."""
        with patch("src.models.xgboost_model.xgb") as mock_xgb:
            from src.models.xgboost_model import XGBoostModel

            mock_classifier = MagicMock()
            mock_classifier.predict_proba.return_value = np.array(
                [
                    [0.7, 0.2, 0.1],
                    [0.1, 0.8, 0.1],
                    [0.2, 0.2, 0.6],
                ]
            )
            mock_xgb.XGBClassifier.return_value = mock_classifier

            model = XGBoostModel()
            model.build()

            x = np.random.randn(3, 10)
            result = model.predict_proba(x)

            assert isinstance(result, np.ndarray)
            assert result.shape == (3, 3)
            np.testing.assert_almost_equal(result.sum(axis=1), [1.0, 1.0, 1.0])

    def test_default_num_classes(self) -> None:
        """Test model defaults to NUM_CLASSES (3) for multi-class classification."""
        with patch("src.models.xgboost_model.xgb"):
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel()
            assert model.params["num_class"] == 3

    def test_regression_task_type(self) -> None:
        """Test model initializes for regression with correct objective."""
        with patch("src.models.xgboost_model.xgb") as _mock_xgb:
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel(task_type="regression")
            assert model.task_type == "regression"
            assert model.params["objective"] == "reg:squarederror"
            assert "num_class" not in model.params

    def test_regression_build_creates_regressor(self) -> None:
        """Test build creates XGBRegressor for regression task."""
        with patch("src.models.xgboost_model.xgb") as mock_xgb:
            from src.models.xgboost_model import XGBoostModel

            model = XGBoostModel(task_type="regression")
            model.build(feature_names=["f1", "f2"])
            mock_xgb.XGBRegressor.assert_called_once()

    def test_regression_fit_returns_metrics(self) -> None:
        """Test fit returns regression metrics for regression task."""
        with (
            patch("src.models.xgboost_model.xgb") as mock_xgb,
            patch("src.models.xgboost_model.mean_squared_error") as mock_mse,
            patch("src.models.xgboost_model.mean_absolute_error") as mock_mae,
            patch("src.models.xgboost_model.r2_score") as mock_r2,
        ):
            from src.models.xgboost_model import XGBoostModel

            mock_regressor = MagicMock()
            mock_regressor.predict.return_value = np.array([1.0, 2.0, 3.0])
            mock_xgb.XGBRegressor.return_value = mock_regressor

            mock_mse.return_value = 0.01
            mock_mae.return_value = 0.05
            mock_r2.return_value = 0.95

            model = XGBoostModel(task_type="regression")
            model.build()

            x_train = np.random.randn(100, 10)
            y_train = np.random.randn(100)
            x_val = np.random.randn(20, 10)
            y_val = np.random.randn(20)

            result = model.fit(x_train, y_train, x_val, y_val)

            assert "rmse" in result
            assert "mae" in result
            assert "r2" in result
