"""Tests for similarity search job."""

from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from config import Config


@pytest.fixture
def config() -> Config:
    return Config(
        symbols=["SYM-A"],
        qdrant_url="http://localhost:6333",
        qdrant_collection="test-embeddings",
        similarity_top_k=5,
        similarity_threshold=0.8,
        similarity_return_field="return",
    )


@pytest.fixture
def mock_qdrant() -> MagicMock:
    with patch("jobs.similarity.QdrantClient") as mock:
        yield mock


@pytest.fixture
def mock_embedding_job() -> MagicMock:
    with patch("jobs.similarity.EmbeddingJob") as mock:
        yield mock


class TestSimilaritySearchJob:
    def test_init(self, config: Config, mock_embedding_job: MagicMock) -> None:
        from jobs.similarity import SimilaritySearchJob

        job = SimilaritySearchJob(config)
        assert job.config == config
        assert job.qdrant is None
        assert job._return_field == "return"

    def test_connect(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        job = SimilaritySearchJob(config)
        job.connect()

        mock_qdrant.assert_called_once_with(url=config.qdrant_url)
        assert job.qdrant is not None

    def test_find_similar_patterns(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        point = MagicMock()
        point.id = 1
        point.score = 0.92
        point.payload = {
            "symbol": "SYM-A",
            "timestamp_unix": datetime(2024, 1, 1, tzinfo=UTC).timestamp(),
            "value": 100.0,
            "return": 0.05,
        }
        mock_qdrant.return_value.query_points.return_value.points = [point]

        job = SimilaritySearchJob(config)
        job.connect()
        query = np.random.randn(768).astype(np.float32)
        patterns = job.find_similar_patterns("SYM-A", query)

        assert len(patterns) == 1
        assert patterns[0]["symbol"] == "SYM-A"
        assert patterns[0]["similarity_score"] == 0.92
        assert patterns[0]["return"] == 0.05

    def test_find_similar_patterns_auto_connects(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_qdrant.return_value.query_points.return_value.points = []

        job = SimilaritySearchJob(config)
        query = np.random.randn(768).astype(np.float32)
        patterns = job.find_similar_patterns("SYM-A", query)

        assert patterns == []
        mock_qdrant.assert_called_once()

    def test_find_similar_patterns_custom_top_k(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_qdrant.return_value.query_points.return_value.points = []

        job = SimilaritySearchJob(config)
        job.connect()
        query = np.random.randn(768).astype(np.float32)
        job.find_similar_patterns("SYM-A", query, top_k=3)

        call_kwargs = mock_qdrant.return_value.query_points.call_args
        assert call_kwargs.kwargs.get("limit") == 3 or call_kwargs[1].get("limit") == 3

    def test_predict_from_similar_no_patterns(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_qdrant.return_value.query_points.return_value.points = []

        job = SimilaritySearchJob(config)
        job.connect()
        query = np.random.randn(768).astype(np.float32)
        result = job.predict_from_similar("SYM-A", query)

        assert result["prediction"] == 0
        assert result["confidence"] == 0
        assert result["num_patterns"] == 0

    def test_predict_from_similar_with_patterns(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        points = []
        for i in range(3):
            p = MagicMock()
            p.id = i
            p.score = 0.9 - i * 0.1
            p.payload = {
                "symbol": "SYM-A",
                "timestamp_unix": 1704067200 + i * 3600,
                "value": 100.0 + i,
                "return": 0.05 if i < 2 else -0.02,
            }
            points.append(p)
        mock_qdrant.return_value.query_points.return_value.points = points

        job = SimilaritySearchJob(config)
        job.connect()
        query = np.random.randn(768).astype(np.float32)
        result = job.predict_from_similar("SYM-A", query)

        assert "predicted_return" in result
        assert "direction" in result
        assert "confidence" in result
        assert result["num_patterns"] == 3
        assert result["direction"] == 1  # 2 positive out of 3
        assert len(result["similar_patterns"]) == 3

    def test_predict_direction_negative(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        points = []
        for i in range(3):
            p = MagicMock()
            p.id = i
            p.score = 0.9
            p.payload = {
                "symbol": "SYM-A",
                "timestamp_unix": 1704067200,
                "value": 100.0,
                "return": -0.05 if i < 2 else 0.02,
            }
            points.append(p)
        mock_qdrant.return_value.query_points.return_value.points = points

        job = SimilaritySearchJob(config)
        job.connect()
        result = job.predict_from_similar("SYM-A", np.zeros(768, dtype=np.float32))

        assert result["direction"] == -1

    def test_run_analysis(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_embedding_job.return_value.get_aggregated_embedding.return_value = (
            np.zeros(768, dtype=np.float32)
        )
        mock_qdrant.return_value.query_points.return_value.points = []

        job = SimilaritySearchJob(config)
        job.connect()
        result = job.run_analysis("SYM-A")

        assert "symbol" in result
        assert "timestamp" in result
        assert "prediction" in result

    def test_run_analysis_no_embedding(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_embedding_job.return_value.get_aggregated_embedding.return_value = None

        job = SimilaritySearchJob(config)
        job.connect()
        result = job.run_analysis("SYM-A")

        assert "error" in result

    def test_run_analysis_auto_connects(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        mock_embedding_job.return_value.get_aggregated_embedding.return_value = None

        job = SimilaritySearchJob(config)
        job.run_analysis("SYM-A")

        mock_qdrant.assert_called_once()

    def test_close(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        job = SimilaritySearchJob(config)
        job.connect()
        job.close()

        assert job.qdrant is None

    def test_close_none(
        self, config: Config, mock_qdrant: MagicMock, mock_embedding_job: MagicMock
    ) -> None:
        from jobs.similarity import SimilaritySearchJob

        job = SimilaritySearchJob(config)
        job.close()  # Should not raise
