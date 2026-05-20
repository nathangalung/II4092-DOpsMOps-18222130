"""Tests for scoring service."""

import os
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest


@pytest.fixture(autouse=True)
def _env_setup(monkeypatch):
    monkeypatch.setenv("MLFLOW_TRACKING_URI", "http://mlflow:5000")
    monkeypatch.setenv("CLICKHOUSE_HOST", "clickhouse")
    monkeypatch.setenv("VALID_SYMBOLS", "SAMPLE-001,SAMPLE-002")
    monkeypatch.setenv("MODEL_TYPE", "lightgbm")
    monkeypatch.setenv("TARGET_COLUMN", "value")
    monkeypatch.setenv("EXCLUDE_COLUMNS", "symbol,timestamp,date,hour")


def test_config_loading():
    from main import Config

    assert Config.MLFLOW_URI == "http://mlflow:5000"
    assert Config.CLICKHOUSE_HOST == "clickhouse"


def test_prepare_input():
    from main import prepare_input

    df = pd.DataFrame({
        "symbol": ["SAMPLE-001"],
        "timestamp": [pd.Timestamp.now()],
        "date": [pd.Timestamp.now().date()],
        "hour": [12],
        "value": [100.0],
        "volume": [50.0],
        "sma_20": [98.0],
        "return_1h": [0.01],
    })

    features = prepare_input(df)
    assert features.shape == (1, 3)  # volume, sma_20, return_1h
    assert features.dtype == np.float32


def test_prepare_input_with_nan():
    from main import prepare_input

    df = pd.DataFrame({
        "symbol": ["SAMPLE-001"],
        "timestamp": [pd.Timestamp.now()],
        "date": [pd.Timestamp.now().date()],
        "hour": [12],
        "value": [100.0],
        "volume": [float("nan")],
        "sma_20": [98.0],
    })

    features = prepare_input(df)
    assert not np.any(np.isnan(features))


def test_prepare_input_no_features():
    from main import prepare_input

    df = pd.DataFrame({
        "symbol": ["SAMPLE-001"],
        "timestamp": [pd.Timestamp.now()],
        "date": [pd.Timestamp.now().date()],
        "hour": [12],
        "value": [100.0],
    })

    with pytest.raises(ValueError, match="No feature columns"):
        prepare_input(df)


def test_prepare_input_with_explicit_feature_columns(monkeypatch):
    monkeypatch.setenv("FEATURE_COLUMNS", "volume,sma_20")
    # Reload config
    import importlib
    import main
    importlib.reload(main)
    from main import prepare_input

    df = pd.DataFrame({
        "symbol": ["SAMPLE-001"],
        "timestamp": [pd.Timestamp.now()],
        "value": [100.0],
        "volume": [50.0],
        "sma_20": [98.0],
        "extra_col": [999.0],
    })

    features = prepare_input(df)
    assert features.shape == (1, 2)  # only volume, sma_20


def test_write_prediction_up_direction():
    from main import write_prediction

    client = MagicMock()
    from datetime import UTC, datetime

    write_prediction(
        client,
        "SAMPLE-001",
        datetime.now(tz=UTC),
        current_value=100.0,
        predicted_value=105.0,
        model_version="abc123",
    )
    client.insert.assert_called_once()
    args = client.insert.call_args
    row = args[0][1][0]
    assert row[4] == "UP"  # direction (>1% increase)


def test_write_prediction_down_direction():
    from main import write_prediction

    client = MagicMock()
    from datetime import UTC, datetime

    write_prediction(
        client,
        "SAMPLE-001",
        datetime.now(tz=UTC),
        current_value=100.0,
        predicted_value=95.0,
        model_version="abc123",
    )
    args = client.insert.call_args
    row = args[0][1][0]
    assert row[4] == "DOWN"  # direction (>1% decrease)


def test_write_prediction_stable_direction():
    from main import write_prediction

    client = MagicMock()
    from datetime import UTC, datetime

    write_prediction(
        client,
        "SAMPLE-001",
        datetime.now(tz=UTC),
        current_value=100.0,
        predicted_value=100.5,
        model_version="abc123",
    )
    args = client.insert.call_args
    row = args[0][1][0]
    assert row[4] == "STABLE"  # direction (<1% change)


@patch("main.ort.InferenceSession")
def test_run_inference(mock_session_cls):
    from main import run_inference

    mock_session = MagicMock()
    mock_session.get_inputs.return_value = [MagicMock(name="input")]
    mock_session.run.return_value = [np.array([[105.0]])]
    mock_session_cls.return_value = mock_session

    result = run_inference(
        "model.onnx",
        np.array([[50.0, 98.0]], dtype=np.float32),
    )
    assert result == 105.0


@patch("main.load_features")
def test_score_symbol_no_features(mock_load):
    from main import score_symbol

    mock_load.return_value = None
    result = score_symbol(MagicMock(), "model.onnx", "SAMPLE-001", "v1")
    assert result is False


def test_load_features():
    from main import load_features

    client = MagicMock()
    client.query_df.return_value = pd.DataFrame({
        "symbol": ["SAMPLE-001"],
        "timestamp": [pd.Timestamp.now()],
        "value": [100.0],
    })

    df = load_features(client, "SAMPLE-001")
    assert df is not None
    assert len(df) == 1


def test_load_features_empty():
    from main import load_features

    client = MagicMock()
    client.query_df.return_value = pd.DataFrame()

    df = load_features(client, "UNKNOWN")
    assert df is None
