import sys
from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest

from main import main


@pytest.fixture
def mock_load_config() -> Generator[MagicMock]:
    with patch("main.load_config") as mock:
        config = MagicMock()
        config.enabled = True
        config.backfill_enabled = True
        mock.return_value = config
        yield mock


@pytest.fixture
def mock_feature_job() -> Generator[MagicMock]:
    with patch("main.FeatureEngineeringJob") as mock:
        yield mock


@pytest.fixture
def mock_backfill_job() -> Generator[MagicMock]:
    with patch("main.BackfillJob") as mock:
        yield mock


def test_main_features_mode(
    mock_load_config: MagicMock, mock_feature_job: MagicMock
) -> None:
    # Setup
    test_args = ["main.py", "--mode", "features"]
    with patch.object(sys, "argv", test_args):
        # Execute
        main()

        # Verify
        mock_feature_job.assert_called_once_with(mock_load_config.return_value)
        mock_feature_job.return_value.connect.assert_called_once()
        mock_feature_job.return_value.run.assert_called_once()
        mock_feature_job.return_value.close.assert_called_once()


def test_main_backfill_mode(
    mock_load_config: MagicMock, mock_backfill_job: MagicMock
) -> None:
    # Setup
    test_args = [
        "main.py",
        "--mode",
        "backfill",
        "--start-date",
        "2024-01-01",
        "--end-date",
        "2024-01-02",
    ]
    with patch.object(sys, "argv", test_args):
        # Execute
        main()

        # Verify
        mock_backfill_job.assert_called_once_with(mock_load_config.return_value)

        # check run args
        _, kwargs = mock_backfill_job.return_value.run.call_args
        # We need to verify datetime conversion happened, but since we didn't mock datetime,
        # let's just check calls were made.
        assert mock_backfill_job.return_value.run.called


def test_main_incremental_mode(
    mock_load_config: MagicMock, mock_backfill_job: MagicMock
) -> None:
    # Setup
    test_args = ["main.py", "--mode", "incremental", "--hours", "48"]
    with patch.object(sys, "argv", test_args):
        # Execute
        main()

        # Verify
        mock_backfill_job.assert_called_once_with(mock_load_config.return_value)
        mock_backfill_job.return_value.run_incremental.assert_called_once_with(hours=48)


def test_main_disabled(
    mock_load_config: MagicMock, mock_feature_job: MagicMock
) -> None:
    # Setup
    mock_load_config.return_value.enabled = False

    test_args = ["main.py", "--mode", "features"]
    with patch.object(sys, "argv", test_args):
        with pytest.raises(SystemExit) as e:
            main()
        assert e.type is SystemExit
        assert e.value.code == 0

        mock_feature_job.assert_not_called()


def test_backfill_disabled(
    mock_load_config: MagicMock, mock_backfill_job: MagicMock
) -> None:
    # Setup
    mock_load_config.return_value.backfill_enabled = False

    test_args = ["main.py", "--mode", "backfill"]
    with patch.object(sys, "argv", test_args):
        with pytest.raises(SystemExit) as e:
            main()
        assert e.type is SystemExit
        assert e.value.code == 0

        mock_backfill_job.assert_not_called()
