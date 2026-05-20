"""Tests for text embedding job."""

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from config import Config


@pytest.fixture
def config() -> Config:
    return Config(
        symbols=["SYM-A"],
        embedding_model="test-model",
        embedding_dim=768,
        qdrant_url="http://localhost:6333",
        qdrant_collection="test-embeddings",
        clickhouse_host="localhost",
        redis_host="localhost",
        embedding_batch_size=2,
        embedding_window_hours=24,
        min_text_length=10,
        similarity_top_k=5,
    )


@pytest.fixture
def mock_deps() -> dict:
    """Mock all external dependencies."""
    patches = {
        "ch": patch("jobs.embedding.clickhouse_connect"),
        "qdrant": patch("jobs.embedding.QdrantClient"),
        "redis": patch("jobs.embedding.redis.Redis"),
        "model": patch("jobs.embedding.SentenceTransformer"),
    }
    mocks = {}
    for key, p in patches.items():
        mocks[key] = p.start()
    # Configure model mock
    mocks["model"].return_value.get_sentence_embedding_dimension.return_value = 768
    mocks["model"].return_value.encode.return_value = np.random.randn(2, 768).astype(
        np.float32
    )
    # Configure qdrant mock
    mocks["qdrant"].return_value.get_collections.return_value.collections = []
    yield mocks
    for p in patches.values():
        p.stop()


class TestTextEmbeddingJob:
    def test_init(self, config: Config) -> None:
        from jobs.embedding import TextEmbeddingJob

        job = TextEmbeddingJob(config)
        assert job.config == config
        assert job.clickhouse is None
        assert job.qdrant is None
        assert job.valkey is None
        assert job.model is None

    def test_connect(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        job = TextEmbeddingJob(config)
        job.connect()

        mock_deps["ch"].get_client.assert_called_once()
        mock_deps["qdrant"].assert_called_once_with(url=config.qdrant_url)
        mock_deps["redis"].assert_called_once()
        mock_deps["model"].assert_called_once()
        assert job.clickhouse is not None
        assert job.qdrant is not None
        assert job.model is not None

    def test_ensure_collection_exists(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        # Collection already exists
        coll = MagicMock()
        coll.name = config.qdrant_collection
        mock_deps["qdrant"].return_value.get_collections.return_value.collections = [
            coll
        ]

        job = TextEmbeddingJob(config)
        job.connect()

        mock_deps["qdrant"].return_value.create_collection.assert_not_called()

    def test_ensure_collection_creates(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["qdrant"].return_value.get_collections.return_value.collections = []

        job = TextEmbeddingJob(config)
        job.connect()

        mock_deps["qdrant"].return_value.create_collection.assert_called_once()

    def test_run_auto_connects(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["ch"].get_client.return_value.query.return_value.result_rows = []

        job = TextEmbeddingJob(config)
        job.run()

        assert job.clickhouse is not None

    def test_run_default_time_range(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.return_value.result_rows = []

        job = TextEmbeddingJob(config)
        job.connect()
        job.run()

        mock_client.query.assert_called()

    def test_run_custom_time_range(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.return_value.result_rows = []

        job = TextEmbeddingJob(config)
        job.connect()
        start = datetime(2024, 1, 1, tzinfo=UTC)
        end = datetime(2024, 1, 2, tzinfo=UTC)
        job.run(start_time=start, end_time=end)

        mock_client.query.assert_called()

    def test_run_handles_process_error(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.side_effect = Exception("DB error")

        job = TextEmbeddingJob(config)
        job.connect()
        job.run()  # Should not raise

    def test_process_symbol_no_data(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.return_value.result_rows = []

        job = TextEmbeddingJob(config)
        job.connect()
        job._process_symbol(
            "SYM-A", datetime.now(tz=UTC) - timedelta(hours=1), datetime.now(tz=UTC)
        )

        mock_deps["qdrant"].return_value.upsert.assert_not_called()

    def test_process_symbol_with_data(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        now = datetime.now(tz=UTC)
        rows = [
            (
                "SYM-A",
                now,
                "source1",
                0.5,
                "positive",
                "This is a test text for embedding",
            ),
            (
                "SYM-A",
                now,
                "source2",
                -0.3,
                "negative",
                "Another test text for embedding",
            ),
        ]
        mock_client = mock_deps["ch"].get_client.return_value
        # First call returns data rows, subsequent calls for aggregation
        agg_result = MagicMock()
        agg_result.result_rows = [(5, 0.5, 0.1, 3, 2)]
        prev_result = MagicMock()
        prev_result.result_rows = [(0.3,)]

        data_result = MagicMock()
        data_result.result_rows = rows
        mock_client.query.side_effect = [
            data_result,
            agg_result,
            prev_result,
            agg_result,
            prev_result,
            agg_result,
            prev_result,
        ]

        job = TextEmbeddingJob(config)
        job.connect()
        job._process_symbol("SYM-A", now - timedelta(hours=1), now)

        mock_deps["qdrant"].return_value.upsert.assert_called()

    def test_write_aggregated_features(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        agg_result = MagicMock()
        agg_result.result_rows = [(10, 0.6, 0.2, 7, 3)]
        prev_result = MagicMock()
        prev_result.result_rows = [(0.4,)]
        mock_client.query.side_effect = [
            agg_result,
            prev_result,
            agg_result,
            prev_result,
            agg_result,
            prev_result,
        ]

        job = TextEmbeddingJob(config)
        job.connect()
        now = datetime.now(tz=UTC)
        job._write_aggregated_features("SYM-A", now - timedelta(hours=24), now)

        mock_client.command.assert_called()
        mock_deps["redis"].return_value.hset.assert_called()
        mock_deps["redis"].return_value.expire.assert_called()

    def test_write_aggregated_no_data(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        empty_result = MagicMock()
        empty_result.result_rows = [(0, None, None, 0, 0)]
        mock_client.query.return_value = empty_result

        job = TextEmbeddingJob(config)
        job.connect()
        now = datetime.now(tz=UTC)
        job._write_aggregated_features("SYM-A", now - timedelta(hours=1), now)

        mock_client.command.assert_not_called()

    def test_store_aggregated_features_insert_failure(
        self, config: Config, mock_deps: dict
    ) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.command.side_effect = Exception("Insert failed")

        job = TextEmbeddingJob(config)
        job.connect()
        now = datetime.now(tz=UTC)
        # Should not raise
        job._store_aggregated_features("SYM-A", now, 1, 10, 0.5, 0.1, 0.7, 0.2)

        mock_deps["redis"].return_value.hset.assert_called()

    def test_search_similar(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["model"].return_value.encode.return_value = np.zeros(
            768, dtype=np.float32
        )
        point = MagicMock()
        point.id = 1
        point.score = 0.95
        point.payload = {
            "symbol": "SYM-A",
            "source": "src",
            "text": "result text",
            "timestamp": "2024-01-01T00:00:00",
            "score": 0.5,
        }
        mock_deps["qdrant"].return_value.query_points.return_value.points = [point]

        job = TextEmbeddingJob(config)
        job.connect()
        results = job.search_similar("test query", symbol="SYM-A", top_k=5)

        assert len(results) == 1
        assert results[0]["symbol"] == "SYM-A"
        assert results[0]["similarity"] == 0.95

    def test_search_similar_no_symbol(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["model"].return_value.encode.return_value = np.zeros(
            768, dtype=np.float32
        )
        mock_deps["qdrant"].return_value.query_points.return_value.points = []

        job = TextEmbeddingJob(config)
        job.connect()
        results = job.search_similar("test query")

        assert results == []

    def test_search_similar_auto_connects(
        self, config: Config, mock_deps: dict
    ) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["model"].return_value.encode.return_value = np.zeros(
            768, dtype=np.float32
        )
        mock_deps["qdrant"].return_value.query_points.return_value.points = []

        job = TextEmbeddingJob(config)
        results = job.search_similar("query")
        assert results == []

    def test_get_aggregated_embedding(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        point = MagicMock()
        point.vector = list(np.ones(768))
        mock_deps["qdrant"].return_value.query_points.return_value.points = [point]

        job = TextEmbeddingJob(config)
        job.connect()
        result = job.get_aggregated_embedding("SYM-A", window_hours=24)

        assert result is not None
        assert result.shape == (768,)

    def test_get_aggregated_embedding_no_results(
        self, config: Config, mock_deps: dict
    ) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_deps["qdrant"].return_value.query_points.return_value.points = []

        job = TextEmbeddingJob(config)
        job.connect()
        result = job.get_aggregated_embedding("SYM-A")

        assert result is None

    def test_close(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        job = TextEmbeddingJob(config)
        job.connect()
        job.close()

        assert job.clickhouse is None
        assert job.qdrant is None
        assert job.valkey is None

    def test_close_none_clients(self, config: Config) -> None:
        from jobs.embedding import TextEmbeddingJob

        job = TextEmbeddingJob(config)
        job.close()  # Should not raise

    def test_run_updates_index_metric(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.return_value.result_rows = []
        info = MagicMock()
        info.points_count = 42
        mock_deps["qdrant"].return_value.get_collection.return_value = info

        job = TextEmbeddingJob(config)
        job.connect()
        job.run()

    def test_run_index_metric_error(self, config: Config, mock_deps: dict) -> None:
        from jobs.embedding import TextEmbeddingJob

        mock_client = mock_deps["ch"].get_client.return_value
        mock_client.query.return_value.result_rows = []
        mock_deps["qdrant"].return_value.get_collection.side_effect = Exception("fail")

        job = TextEmbeddingJob(config)
        job.connect()
        job.run()  # Should not raise


class TestEmbeddingJobAlias:
    def test_alias_inherits(self) -> None:
        from jobs.embedding import EmbeddingJob, TextEmbeddingJob

        assert issubclass(EmbeddingJob, TextEmbeddingJob)


class TestDistanceMap:
    def test_distance_map(self) -> None:
        from jobs.embedding import DISTANCE_MAP

        assert "Cosine" in DISTANCE_MAP
        assert "Euclid" in DISTANCE_MAP
        assert "Dot" in DISTANCE_MAP
