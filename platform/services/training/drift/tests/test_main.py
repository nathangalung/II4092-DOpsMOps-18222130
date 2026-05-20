import datetime
from unittest.mock import MagicMock, patch

from main import (
    check_scale,
    load_config,
    parse_duration,
    query_feature_data,
)

# --- Helper Tests ---


def test_parse_duration() -> None:
    assert parse_duration("60m") == datetime.timedelta(minutes=60)
    assert parse_duration("24h") == datetime.timedelta(hours=24)
    assert parse_duration("30d") == datetime.timedelta(days=30)
    assert parse_duration("10x") == datetime.timedelta(hours=1)  # Default fallback


def test_query_feature_data() -> None:
    mock_client = MagicMock()
    mock_result = MagicMock()
    mock_result.result_rows = [[1.0], [2.0], [3.0]]
    mock_client.query.return_value = mock_result

    start = datetime.datetime(2024, 1, 1)
    end = datetime.datetime(2024, 1, 2)

    data = query_feature_data(mock_client, "value_1", start, end)

    assert len(data) == 3
    assert data[0] == 1.0
    mock_client.query.assert_called_once()
    query = mock_client.query.call_args[0][0]
    assert "value_1" in query


# --- check_scale Tests ---


@patch("main.calculate_psi")
@patch("main.ks_test")
@patch("main.query_feature_data")
@patch("main.DRIFT_PSI")
@patch("main.DRIFT_KS")
@patch("main.DRIFT_DETECTED")
def test_check_scale_detects_drift(
    mock_drift_detected: MagicMock,
    mock_drift_ks: MagicMock,
    mock_drift_psi: MagicMock,
    mock_query: MagicMock,
    mock_ks_test: MagicMock,
    mock_psi: MagicMock,
) -> None:
    import numpy as np

    mock_ch = MagicMock()
    mock_valkey = MagicMock()

    # Return enough data for both windows
    mock_query.return_value = np.array([1.0] * 20)

    # Severe drift
    mock_psi.return_value = 0.25
    mock_ks_test.return_value = (0.5, 0.01)

    scale_config = {
        "reference_window": "24h",
        "comparison_window": "1h",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.03,
        "trigger_retrain": True,
    }

    drift_count = check_scale(
        mock_ch, mock_valkey, "hour", scale_config, ["feature1"]
    )

    assert drift_count == 1
    mock_psi.assert_called_once()
    mock_ks_test.assert_called_once()
    mock_drift_detected.labels.assert_called()
    mock_valkey.publish.assert_called_once()
    args = mock_valkey.publish.call_args
    assert args[0][0] == "drift-events"
    assert "hour:feature1:0.2500" in args[0][1]


@patch("main.calculate_psi")
@patch("main.ks_test")
@patch("main.query_feature_data")
@patch("main.DRIFT_PSI")
@patch("main.DRIFT_KS")
@patch("main.DRIFT_DETECTED")
def test_check_scale_no_drift(
    mock_drift_detected: MagicMock,
    mock_drift_ks: MagicMock,
    mock_drift_psi: MagicMock,
    mock_query: MagicMock,
    mock_ks_test: MagicMock,
    mock_psi: MagicMock,
) -> None:
    import numpy as np

    mock_ch = MagicMock()
    mock_valkey = MagicMock()

    mock_query.return_value = np.array([1.0] * 20)
    mock_psi.return_value = 0.05  # Below threshold
    mock_ks_test.return_value = (0.1, 0.50)  # High p-value = no drift

    scale_config = {
        "reference_window": "24h",
        "comparison_window": "1h",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.03,
        "trigger_retrain": True,
    }

    drift_count = check_scale(
        mock_ch, mock_valkey, "hour", scale_config, ["feature1"]
    )

    assert drift_count == 0
    mock_valkey.publish.assert_not_called()


@patch("main.query_feature_data")
def test_check_scale_insufficient_data(mock_query: MagicMock) -> None:
    import numpy as np

    mock_ch = MagicMock()
    mock_valkey = MagicMock()

    # Not enough data
    mock_query.return_value = np.array([1.0] * 3)

    scale_config = {
        "reference_window": "24h",
        "comparison_window": "1h",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.03,
        "trigger_retrain": False,
    }

    drift_count = check_scale(
        mock_ch, mock_valkey, "hour", scale_config, ["feature1"]
    )

    assert drift_count == 0


def test_load_config_fallback() -> None:
    with patch("builtins.open", side_effect=Exception):
        config = load_config()
        assert "scales" in config
        assert "hour" in config["scales"]
        assert "daily" in config["scales"]
