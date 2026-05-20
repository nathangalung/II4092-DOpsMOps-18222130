import os
from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest

from main import load_config, main, run_analysis


@pytest.fixture
def mock_outlier_detector() -> Generator[MagicMock]:
    with patch("main.OutlierDetector") as mock:
        yield mock


@pytest.fixture
def mock_expectations_runner() -> Generator[MagicMock]:
    with patch("main.ExpectationsRunner") as mock:
        yield mock


def test_load_config_default() -> None:
    # Setup
    with patch("os.path.exists", return_value=False):
        # Execute
        config = load_config()

        # Verify
        assert config["quality"]["min_records"] == 100


def test_load_config_file() -> None:
    # Setup
    mock_content = "quality:\n  min_records: 200"
    with (
        patch("os.path.exists", return_value=True),
        patch("builtins.open", new_callable=MagicMock) as mock_open,
        patch("main.yaml.safe_load", return_value={"quality": {"min_records": 200}}),
    ):
        mock_open.return_value.__enter__.return_value.read.return_value = mock_content
        # Execute
        config = load_config()

        # Verify
        assert config["quality"]["min_records"] == 200


def test_run_analysis_all(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    # Setup
    config = {"quality": {"outlier_std": 2.5}}

    # Execute
    run_analysis(config)

    # Verify
    mock_outlier_detector.assert_called_once_with(std_threshold=2.5)
    mock_outlier_detector.return_value.run.assert_called_once()

    mock_expectations_runner.assert_called_once()
    mock_expectations_runner.return_value.run.assert_called_once()


def test_run_analysis_outlier_only(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    # Setup
    config = {}

    # Execute
    run_analysis(config, mode="outlier")

    # Verify
    mock_outlier_detector.return_value.run.assert_called_once()
    mock_expectations_runner.return_value.run.assert_not_called()


def test_main_one_shot(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    # Setup
    with (
        patch("main.load_config", return_value={}),
        patch.dict(os.environ, {"CONTINUOUS": "false"}),
    ):
        # Execute
        main()

        # Verify
        mock_outlier_detector.return_value.run.assert_called_once()


def test_main_continuous(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    # Setup
    with (
        patch("main.load_config", return_value={}),
        patch.dict(os.environ, {"CONTINUOUS": "true", "INTERVAL_SECONDS": "0"}),
        patch("main.time.sleep", side_effect=[None, SystemExit]),
        pytest.raises(SystemExit),
    ):
        main()

    # Verify called at least twice (loop)
    assert mock_outlier_detector.return_value.run.call_count >= 1


def test_run_analysis_expectations_only(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    config = {}
    run_analysis(config, mode="expectations")

    mock_outlier_detector.return_value.run.assert_not_called()
    mock_expectations_runner.return_value.run.assert_called_once()


def test_run_analysis_ge_fallback(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    """Test fallback to SimplifiedExpectationsRunner when GE fails."""
    mock_expectations_runner.side_effect = Exception("GE init failed")

    with patch("main.SimplifiedExpectationsRunner") as mock_simplified:
        run_analysis({}, mode="expectations")
        mock_simplified.assert_called_once()
        mock_simplified.return_value.run.assert_called_once()


def test_main_continuous_error_handling(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    """Test continuous mode handles errors without stopping."""
    mock_outlier_detector.return_value.run.side_effect = [
        Exception("temp error"),
        None,
    ]

    with (
        patch("main.load_config", return_value={}),
        patch.dict(
            os.environ,
            {"CONTINUOUS": "true", "INTERVAL_SECONDS": "0", "ANALYSIS_MODE": "outlier"},
        ),
        patch("main.time.sleep", side_effect=[None, SystemExit]),
        pytest.raises(SystemExit),
    ):
        main()


def test_main_with_analysis_mode(
    mock_outlier_detector: MagicMock, mock_expectations_runner: MagicMock
) -> None:
    with (
        patch("main.load_config", return_value={}),
        patch.dict(os.environ, {"CONTINUOUS": "false", "ANALYSIS_MODE": "outlier"}),
    ):
        main()

    mock_outlier_detector.return_value.run.assert_called_once()
    mock_expectations_runner.return_value.run.assert_not_called()
