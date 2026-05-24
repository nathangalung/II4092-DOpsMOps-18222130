"""Tests for Evidently reporter service (Evidently 0.7+ API)."""

from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest


@pytest.fixture(autouse=True)
def _env_setup(monkeypatch):
    monkeypatch.setenv("CLICKHOUSE_HOST", "clickhouse")
    monkeypatch.setenv("EVIDENTLY_HOST", "evidently")
    monkeypatch.setenv("EVIDENTLY_PORT", "8000")
    monkeypatch.setenv("VALID_SYMBOLS", "SYMBOL-1,SYMBOL-2")
    monkeypatch.setenv("TARGET_COLUMN", "value")
    monkeypatch.setenv("EXCLUDE_COLUMNS", "symbol,timestamp,date,hour")
    monkeypatch.setenv("REFERENCE_WINDOW_HOURS", "72")
    monkeypatch.setenv("CURRENT_WINDOW_HOURS", "24")


def test_config_loading():
    from main import Config

    assert Config.CLICKHOUSE_HOST == "clickhouse"
    assert Config.EVIDENTLY_HOST == "evidently"
    assert Config.REFERENCE_WINDOW_HOURS == 72
    assert Config.CURRENT_WINDOW_HOURS == 24


def test_get_feature_columns():
    from main import get_feature_columns

    df = pd.DataFrame({
        "symbol": ["SYMBOL-1"],
        "timestamp": [pd.Timestamp.now()],
        "date": [pd.Timestamp.now().date()],
        "hour": [12],
        "value": [70000.0],
        "volume": [100.0],
        "sma_20": [69000.0],
    })

    cols = get_feature_columns(df)
    assert "value" in cols
    assert "volume" in cols
    assert "sma_20" in cols
    assert "symbol" not in cols
    assert "timestamp" not in cols


def test_generate_drift_report():
    from main import generate_drift_report

    np.random.seed(42)
    n = 50
    feature_cols = ["value", "volume", "sma_20"]
    reference = pd.DataFrame({
        "value": np.random.normal(70000, 1000, n),
        "volume": np.random.normal(100, 20, n),
        "sma_20": np.random.normal(69500, 500, n),
    })
    current = pd.DataFrame({
        "value": np.random.normal(70500, 1200, n),
        "volume": np.random.normal(110, 25, n),
        "sma_20": np.random.normal(70000, 600, n),
    })

    snapshot = generate_drift_report(reference, current, feature_cols)
    assert snapshot is not None
    # Snapshot should have json() and save_html() methods
    assert hasattr(snapshot, "json")
    assert hasattr(snapshot, "save_html")


def test_generate_summary_report():
    from main import generate_summary_report

    np.random.seed(42)
    n = 50
    feature_cols = ["value", "volume"]
    reference = pd.DataFrame({
        "value": np.random.normal(70000, 1000, n),
        "volume": np.random.normal(100, 20, n),
    })
    current = pd.DataFrame({
        "value": np.random.normal(70500, 1200, n),
        "volume": np.random.normal(110, 25, n),
    })

    snapshot = generate_summary_report(reference, current, feature_cols)
    assert snapshot is not None


def test_load_data():
    from datetime import UTC, datetime

    from main import load_data

    client = MagicMock()
    client.query_df.return_value = pd.DataFrame({
        "symbol": ["SYMBOL-1"] * 5,
        "value": [70000.0] * 5,
    })

    df = load_data(client, "SYMBOL-1", datetime.now(tz=UTC), datetime.now(tz=UTC))
    assert len(df) == 5


def test_load_data_empty():
    from datetime import UTC, datetime

    from main import load_data

    client = MagicMock()
    client.query_df.return_value = pd.DataFrame()

    df = load_data(client, "UNKNOWN", datetime.now(tz=UTC), datetime.now(tz=UTC))
    assert len(df) == 0


@patch("main.requests.get")
def test_ensure_project_existing(mock_get):
    from main import ensure_project

    mock_get.return_value = MagicMock(
        status_code=200,
        json=lambda: [{"name": "pipeline-monitoring", "id": "proj-123"}],
    )
    mock_get.return_value.raise_for_status = lambda: None

    project_id = ensure_project("http://evidently:8000")
    assert project_id == "proj-123"


@patch("main.requests.post")
@patch("main.requests.get")
def test_ensure_project_create_new(mock_get, mock_post):
    from main import ensure_project

    mock_get.return_value = MagicMock(
        status_code=200,
        json=lambda: [],
    )
    mock_get.return_value.raise_for_status = lambda: None

    mock_post.return_value = MagicMock(
        status_code=200,
        json=lambda: {"id": "new-proj-456"},
    )
    mock_post.return_value.raise_for_status = lambda: None

    project_id = ensure_project("http://evidently:8000")
    assert project_id == "new-proj-456"


@patch("main.requests.get")
def test_ensure_project_connection_error(mock_get):
    from main import ensure_project

    mock_get.side_effect = ConnectionError("refused")

    project_id = ensure_project("http://evidently:8000")
    assert project_id is None


def test_process_symbol_insufficient_ref_data():
    from main import process_symbol

    client = MagicMock()
    client.query_df.return_value = pd.DataFrame({"value": [1.0] * 3})

    count = process_symbol(client, "SYMBOL-1", ["drift"], "http://e:8000", None)
    assert count == 0
