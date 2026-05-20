import os
import sys
from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest

from main import main

DEFAULT_SYMBOL = os.getenv("DEFAULT_SYMBOL", "SAMPLE-001")


@pytest.fixture
def mock_load_config() -> Generator[MagicMock]:
    with patch("main.load_config") as mock:
        config = MagicMock()
        config.enabled = True
        mock.return_value = config
        yield mock


@pytest.fixture
def mock_embedding_job() -> Generator[MagicMock]:
    with patch("main.EmbeddingJob") as mock:
        yield mock


@pytest.fixture
def mock_similarity_job() -> Generator[MagicMock]:
    with patch("main.SimilaritySearchJob") as mock:
        yield mock


def test_main_embeddings_mode(
    mock_load_config: MagicMock, mock_embedding_job: MagicMock
) -> None:
    # Setup
    test_args = ["main.py", "--mode", "embeddings", "--start-date", "2024-01-01"]
    with patch.object(sys, "argv", test_args):
        # Execute
        main()

        # Verify
        mock_embedding_job.assert_called_once_with(mock_load_config.return_value)
        mock_embedding_job.return_value.connect.assert_called_once()
        mock_embedding_job.return_value.run.assert_called_once()
        mock_embedding_job.return_value.close.assert_called_once()


def test_main_analysis_mode(
    mock_load_config: MagicMock, mock_similarity_job: MagicMock
) -> None:
    # Setup
    test_args = ["main.py", "--mode", "analysis", "--symbol", "SAMPLE-001"]

    mock_similarity_job.return_value.run_analysis.return_value = {"matches": []}

    with patch.object(sys, "argv", test_args):
        # Execute
        main()

        # Verify
        mock_similarity_job.assert_called_once_with(mock_load_config.return_value)
        mock_similarity_job.return_value.connect.assert_called_once()
        mock_similarity_job.return_value.run_analysis.assert_called_once_with(
            "SAMPLE-001"
        )
        mock_similarity_job.return_value.close.assert_called_once()


def test_main_disabled(
    mock_load_config: MagicMock, mock_embedding_job: MagicMock
) -> None:
    # Setup
    mock_load_config.return_value.enabled = False

    test_args = ["main.py", "--mode", "embeddings"]
    with patch.object(sys, "argv", test_args):
        with pytest.raises(SystemExit) as e:
            main()
        assert e.type is SystemExit
        assert e.value.code == 0

        mock_embedding_job.assert_not_called()
