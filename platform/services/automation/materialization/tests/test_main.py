import os
from collections.abc import Generator
from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest

from main import main


@pytest.fixture
def mock_feast_feature_store() -> Generator[MagicMock]:
    with patch("main.FeatureStore") as mock:
        yield mock


def test_main_materialization(mock_feast_feature_store: MagicMock) -> None:
    # Setup
    mock_store_instance = MagicMock()
    mock_feast_feature_store.return_value = mock_store_instance

    # Mock datetime to have a fixed "now"
    fixed_now = datetime(2024, 1, 2, 12, 0, 0, tzinfo=UTC)

    with (
        patch("main.datetime") as mock_datetime,
        patch("main.subprocess.run") as mock_subprocess,
    ):
        mock_datetime.now.return_value = fixed_now
        mock_datetime.side_effect = lambda *a, **kw: datetime(*a, **kw)
        mock_subprocess.return_value = MagicMock(returncode=0, stdout="Applied", stderr="")

        # Execute
        main()

        # Verify subprocess.run was called for feast apply
        mock_subprocess.assert_called_once()

        # Verify FeatureStore was initialized with correct path
        mock_feast_feature_store.assert_called_once_with(repo_path="/app/feature_repo")

        # Verify materialize was called
        mock_store_instance.materialize.assert_called_once()

        # Check args
        _args, kwargs = mock_store_instance.materialize.call_args
        start_date = kwargs.get("start_date")
        end_date = kwargs.get("end_date")

        assert end_date == fixed_now
        assert start_date == fixed_now - timedelta(hours=24)


def test_main_custom_repo_path(mock_feast_feature_store: MagicMock) -> None:
    # Setup
    custom_path = "/custom/repo/path"
    with (
        patch.dict(os.environ, {"FEAST_REPO_PATH": custom_path}),
        patch("main.datetime") as mock_datetime,
        patch("main.subprocess.run") as mock_subprocess,
    ):
        mock_datetime.now.return_value = datetime(2024, 1, 1, tzinfo=UTC)
        mock_subprocess.return_value = MagicMock(returncode=0, stdout="Applied", stderr="")

        # Execute
        main()

        # Verify
        mock_feast_feature_store.assert_called_once_with(repo_path=custom_path)
