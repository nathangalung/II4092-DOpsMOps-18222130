"""Tests for vector processing configuration."""

import os
from unittest.mock import patch

import pytest
import yaml

from config import Config, load_config


class TestConfig:
    def test_config_defaults(self) -> None:
        config = Config()
        assert config.project_name == "ml-pipeline"
        assert config.timezone == "UTC"
        assert config.enabled is True
        assert config.embedding_dim == 768
        assert config.max_sequence_length == 512
        assert config.embedding_batch_size == 32
        assert config.embedding_window_hours == 24
        assert config.min_text_length == 50
        assert config.qdrant_url == "http://localhost:6333"
        assert config.qdrant_grpc_url == "localhost:6334"
        assert config.distance_metric == "Cosine"
        assert config.hnsw_m == 16
        assert config.hnsw_ef_construct == 200
        assert config.similarity_top_k == 10
        assert config.similarity_threshold == 0.8
        assert config.clickhouse_host == "localhost"
        assert config.clickhouse_port == 8123
        assert config.clickhouse_database == "features"
        assert config.redis_host == "localhost"
        assert config.redis_port == 6379

    def test_config_custom_values(self) -> None:
        config = Config(
            project_name="test",
            embedding_model="test-model",
            embedding_dim=384,
            qdrant_url="http://qdrant:6333",
        )
        assert config.project_name == "test"
        assert config.embedding_model == "test-model"
        assert config.embedding_dim == 384
        assert config.qdrant_url == "http://qdrant:6333"


class TestLoadConfig:
    def test_load_no_file(self) -> None:
        with patch("os.path.exists", return_value=False):
            config = load_config("/nonexistent.yaml")
        assert config.project_name == "ml-pipeline"
        assert config.enabled is True

    def test_load_from_yaml(self, tmp_path: pytest.TempPathFactory) -> None:
        yaml_content = {
            "project": {"name": "test-project", "timezone": "Asia/Jakarta"},
            "data_source": {"api": {"symbols": ["SYM-A", "SYM-B"]}},
            "services": {
                "processing": {
                    "vector": {
                        "enabled": True,
                        "model": {
                            "name": "custom-model",
                            "dimension": 384,
                            "max_sequence_length": 256,
                            "batch_size": 16,
                        },
                        "qdrant": {
                            "url": "http://qdrant:6333",
                            "grpc_url": "qdrant:6334",
                            "collection": "test-col",
                            "distance_metric": "Euclid",
                            "hnsw_m": 32,
                            "hnsw_ef_construct": 100,
                        },
                        "processing": {
                            "window_hours": 48,
                            "min_text_length": 100,
                            "similarity_threshold": 0.9,
                            "return_field": "value_change",
                        },
                    }
                }
            },
            "infrastructure": {
                "clickhouse": {"host": "ch-host", "port": 9000, "database": "test_db"},
                "redis": {"host": "redis-host", "port": 6380},
            },
        }
        config_file = tmp_path / "config.yaml"
        config_file.write_text(yaml.dump(yaml_content))

        config = load_config(str(config_file))

        assert config.project_name == "test-project"
        assert config.timezone == "Asia/Jakarta"
        assert config.symbols == ["SYM-A", "SYM-B"]
        assert config.embedding_model == "custom-model"
        assert config.embedding_dim == 384
        assert config.max_sequence_length == 256
        assert config.embedding_batch_size == 16
        assert config.qdrant_url == "http://qdrant:6333"
        assert config.qdrant_grpc_url == "qdrant:6334"
        assert config.qdrant_collection == "test-col"
        assert config.distance_metric == "Euclid"
        assert config.hnsw_m == 32
        assert config.hnsw_ef_construct == 100
        assert config.embedding_window_hours == 48
        assert config.min_text_length == 100
        assert config.similarity_threshold == 0.9
        assert config.similarity_return_field == "value_change"
        assert config.clickhouse_host == "ch-host"
        assert config.clickhouse_port == 9000
        assert config.clickhouse_database == "test_db"
        assert config.redis_host == "redis-host"
        assert config.redis_port == 6380

    def test_env_overrides(self) -> None:
        env = {
            "VECTOR_ENABLED": "false",
            "EMBEDDING_MODEL": "env-model",
            "EMBEDDING_DIM": "256",
            "EMBEDDING_WINDOW_HOURS": "12",
            "MIN_TEXT_LENGTH": "25",
            "QDRANT_URL": "http://env-qdrant:6333",
            "QDRANT_GRPC_URL": "env-qdrant:6334",
            "VECTOR_COLLECTION": "env-col",
            "SIMILARITY_RETURN_FIELD": "env_return",
            "CLICKHOUSE_HOST": "env-ch",
            "CLICKHOUSE_PORT": "9999",
            "CLICKHOUSE_DATABASE": "env_db",
            "VALKEY_HOST": "env-redis",
            "VALKEY_PORT": "6381",
        }
        with (
            patch("os.path.exists", return_value=False),
            patch.dict(os.environ, env),
        ):
            config = load_config()

        assert config.enabled is False
        assert config.embedding_model == "env-model"
        assert config.embedding_dim == 256
        assert config.embedding_window_hours == 12
        assert config.min_text_length == 25
        assert config.qdrant_url == "http://env-qdrant:6333"
        assert config.qdrant_grpc_url == "env-qdrant:6334"
        assert config.qdrant_collection == "env-col"
        assert config.similarity_return_field == "env_return"
        assert config.clickhouse_host == "env-ch"
        assert config.clickhouse_port == 9999
        assert config.clickhouse_database == "env_db"
        assert config.redis_host == "env-redis"
        assert config.redis_port == 6381

    def test_default_config_path_env(self) -> None:
        with (
            patch("os.path.exists", return_value=False),
            patch.dict(os.environ, {"CONFIG_PATH": "/custom/path.yaml"}),
        ):
            config = load_config()
        assert isinstance(config, Config)

    def test_yaml_empty_sections(self, tmp_path: pytest.TempPathFactory) -> None:
        config_file = tmp_path / "config.yaml"
        config_file.write_text(yaml.dump({"project": {}, "services": {}}))
        config = load_config(str(config_file))
        assert config.project_name == "ml-pipeline"
