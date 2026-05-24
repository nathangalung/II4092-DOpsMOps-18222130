"""Tests for model factory."""

import os
from unittest.mock import patch

import pytest

from src.model_factory import REGISTRY, create_model, get_framework


class TestCreateModel:
    """Tests for create_model function."""

    def test_create_lstm(self) -> None:
        model = create_model("lstm")
        assert type(model).__name__ == "LSTMModel"

    def test_create_xgboost(self) -> None:
        model = create_model("xgboost")
        assert type(model).__name__ == "XGBoostModel"

    def test_create_lightgbm(self) -> None:
        model = create_model("lightgbm")
        assert type(model).__name__ == "LightGBMModel"

    def test_create_catboost(self) -> None:
        model = create_model("catboost")
        assert type(model).__name__ == "CatBoostModel"

    def test_create_random_forest(self) -> None:
        model = create_model("random_forest")
        assert type(model).__name__ == "RandomForestModel"

    def test_create_ridge(self) -> None:
        model = create_model("ridge")
        assert type(model).__name__ == "RidgeModel"

    def test_unknown_type_raises_error(self) -> None:
        with pytest.raises(ValueError, match="Unknown model type: invalid_model"):
            create_model("invalid_model")

    def test_error_message_lists_available(self) -> None:
        with pytest.raises(ValueError, match="Available:"):
            create_model("nonexistent")

    def test_default_is_lstm(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            os.environ.pop("MODEL_TYPE", None)
            model = create_model()
            assert type(model).__name__ == "LSTMModel"

    def test_env_var_override(self) -> None:
        with patch.dict(os.environ, {"MODEL_TYPE": "xgboost"}):
            model = create_model()
            assert type(model).__name__ == "XGBoostModel"

    def test_explicit_type_overrides_env(self) -> None:
        with patch.dict(os.environ, {"MODEL_TYPE": "xgboost"}):
            model = create_model("lightgbm")
            assert type(model).__name__ == "LightGBMModel"

    def test_kwargs_forwarded(self) -> None:
        model = create_model("xgboost", max_depth=10, n_estimators=200)
        assert model.params["max_depth"] == 10
        assert model.params["n_estimators"] == 200

    def test_registry_completeness(self) -> None:
        expected = {"lstm", "xgboost", "lightgbm", "catboost", "random_forest", "ridge"}
        assert set(REGISTRY.keys()) == expected


class TestGetFramework:
    def test_lstm_is_tensorflow(self) -> None:
        assert get_framework("lstm") == "tensorflow"

    def test_xgboost_is_sklearn(self) -> None:
        assert get_framework("xgboost") == "sklearn"

    def test_lightgbm_is_sklearn(self) -> None:
        assert get_framework("lightgbm") == "sklearn"

    def test_unknown_defaults_sklearn(self) -> None:
        assert get_framework("unknown") == "sklearn"
