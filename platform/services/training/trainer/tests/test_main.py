import os
import sys
from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

# Add src to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../src")))

from main import load_data, main, train_models


@pytest.fixture
def mock_clickhouse() -> Generator[MagicMock]:
    with patch("main.clickhouse_connect") as mock:
        yield mock


@pytest.fixture
def mock_mlflow() -> Generator[MagicMock]:
    with patch("main.mlflow") as mock:
        yield mock


@pytest.fixture
def mock_trainer() -> Generator[MagicMock]:
    with patch("main.Trainer") as mock:
        yield mock


@pytest.fixture
def mock_create_model() -> Generator[MagicMock]:
    with patch("main.create_model") as mock:
        yield mock


@pytest.fixture
def mock_exporter() -> Generator[MagicMock]:
    with patch("main.ONNXExporter") as mock:
        yield mock


def test_load_data(mock_clickhouse: MagicMock) -> None:
    mock_df = pd.DataFrame(
        {
            "timestamp": [1, 2],
            "value": [100, 101],
            "feature_1": [0.1, None],
        }
    )
    mock_clickhouse.get_client.return_value.query_df.return_value = mock_df

    df = load_data("SYMBOL-A", "2024-01-01", "2024-01-02")

    assert len(df) == 2
    assert df["feature_1"].isna().sum() == 0


@patch("main.get_task_type", return_value="regression")
def test_train_models_regression(
    _mock_task_type: MagicMock,
    mock_mlflow: MagicMock,
    mock_trainer: MagicMock,
    mock_create_model: MagicMock,
    mock_exporter: MagicMock,
) -> None:
    mock_df = pd.DataFrame({"value": [100]})
    mock_model = MagicMock()
    mock_create_model.return_value = mock_model
    mock_trainer.return_value.train_regression.return_value = {"mse": 0.05}
    mock_trainer.return_value.feature_cols = ["f1", "f2"]

    with patch.dict(os.environ, {"MODEL_TYPE": "lightgbm"}):
        results = train_models("SYMBOL-A", mock_df)

    assert "lightgbm" in results
    mock_create_model.assert_called_once()
    mock_trainer.return_value.train_regression.assert_called_once()
    mock_exporter.return_value.export_model.assert_called_once()
    mock_mlflow.log_artifact.assert_called()
    mock_mlflow.log_param.assert_any_call("model_type", "lightgbm")


@patch("main.get_task_type", return_value="time_series")
def test_train_models_time_series(
    _mock_task_type: MagicMock,
    mock_mlflow: MagicMock,
    mock_trainer: MagicMock,
    mock_create_model: MagicMock,
    mock_exporter: MagicMock,
) -> None:
    mock_df = pd.DataFrame({"value": [100]})
    mock_model = MagicMock()
    mock_create_model.return_value = mock_model
    mock_trainer.return_value.train_time_series.return_value = {"val_loss": 0.1}

    with patch.dict(os.environ, {"MODEL_TYPE": "lstm"}):
        results = train_models("SYMBOL-A", mock_df)

    assert "lstm" in results
    mock_exporter.return_value.export_keras.assert_called_once()
    mock_mlflow.log_param.assert_any_call("framework", "tensorflow")


def test_main_trains_all_symbols(
    mock_clickhouse: MagicMock,
    mock_mlflow: MagicMock,
    mock_trainer: MagicMock,
    mock_create_model: MagicMock,
    mock_exporter: MagicMock,
) -> None:
    mock_df = pd.DataFrame({"value": range(200)})
    mock_clickhouse.get_client.return_value.query_df.return_value = mock_df
    mock_trainer.return_value.train_regression.return_value = {"mse": 0.05}
    mock_trainer.return_value.feature_cols = ["f1"]

    with (
        patch.dict(os.environ, {
            "VALID_SYMBOLS": "SAMPLE-001,SAMPLE-002",
            "MODEL_TYPE": "lightgbm",
        }),
        patch("sys.argv", ["main.py", "--train-all"]),
    ):
        main()

    # Should be called twice (SAMPLE-001 + SAMPLE-002)
    assert mock_create_model.call_count == 2


def test_main_not_enough_data(
    mock_clickhouse: MagicMock, mock_trainer: MagicMock
) -> None:
    mock_df = pd.DataFrame({"value": range(10)})
    mock_clickhouse.get_client.return_value.query_df.return_value = mock_df

    with patch("sys.argv", ["main.py"]):
        main()

    mock_trainer.assert_not_called()
