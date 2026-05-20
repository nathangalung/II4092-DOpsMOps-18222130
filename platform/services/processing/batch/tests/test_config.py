"""Tests for configuration loader."""

import os
import tempfile
from collections.abc import Generator
from typing import Any

import pytest
import yaml

from config import Config, load_config


@pytest.fixture
def sample_config_data() -> dict[str, Any]:
    """Sample configuration data."""
    return {
        "project": {
            "name": "test-project",
            "timezone": "UTC",
        },
        "data_source": {
            "api": {"symbols": ["SYMBOL-A", "SYMBOL-B"]},
        },
        "services": {
            "processing": {
                "batch": {
                    "enabled": True,
                    "schedule": "0 * * * *",
                    "backfill_enabled": True,
                }
            }
        },
        "features": {
            "data_columns": ["value_1", "value_2", "value_3", "value_4", "value_5"],
            "technical_indicators": {"moving_averages": {"rolling_mean": [20]}},
            "time_features_enabled": True,
            "lag_columns": ["value_4", "value_5"],
            "lag_periods": [1, 6],
            "return_periods": [1, 6],
            "return_column": "value_4",
            "target_horizons": [1],
            "target_column": "value_4",
            "dispersion_windows": [1, 24],
        },
        "infrastructure": {
            "clickhouse": {
                "host": "clickhouse-test",
                "port": 8123,
                "database": "test_db",
            },
            "kafka": {
                "brokers": "kafka:9092",
                "topics": {"raw": "raw-topic", "features": "features-topic"},
            },
        },
        "data_splits": {
            "train": {"start": "2024-01-01T00:00:00", "end": "2024-06-01T00:00:00"},
            "validation": {
                "start": "2024-06-01T00:00:00",
                "end": "2024-07-01T00:00:00",
            },
        },
    }


@pytest.fixture
def config_file(sample_config_data: dict[str, Any]) -> Generator[str]:
    """Create temporary config file."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
        yaml.dump(sample_config_data, f)
        yield f.name
    os.unlink(f.name)


class TestLoadConfig:
    def test_load_from_path(self, config_file: str) -> None:
        config = load_config(config_file)
        assert isinstance(config, Config)
        assert config.project_name == "test-project"

    def test_project_settings(self, config_file: str) -> None:
        config = load_config(config_file)
        assert config.project_name == "test-project"
        assert config.timezone == "UTC"
        assert config.symbols == ["SYMBOL-A", "SYMBOL-B"]

    def test_processing_settings(self, config_file: str) -> None:
        config = load_config(config_file)
        assert config.enabled is True
        assert config.schedule == "0 * * * *"
        assert config.backfill_enabled is True

    def test_feature_settings(self, config_file: str) -> None:
        config = load_config(config_file)
        assert config.data_columns == [
            "value_1",
            "value_2",
            "value_3",
            "value_4",
            "value_5",
        ]
        assert config.lag_columns == ["value_4", "value_5"]
        assert config.lag_periods == [1, 6]
        assert config.return_periods == [1, 6]

    def test_infrastructure_settings(self, config_file: str) -> None:
        config = load_config(config_file)
        assert config.clickhouse_host == "clickhouse-test"
        assert config.clickhouse_port == 8123
        assert config.clickhouse_database == "test_db"
        assert config.kafka_brokers == "kafka:9092"

    def test_data_splits(self, config_file: str) -> None:
        config = load_config(config_file)
        assert config.train_start == "2024-01-01T00:00:00"
        assert config.train_end == "2024-06-01T00:00:00"
        assert config.validation_start == "2024-06-01T00:00:00"

    def test_default_values(self) -> None:
        """Test defaults when config has missing sections."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
            yaml.dump({}, f)
            f.flush()
            config = load_config(f.name)
        os.unlink(f.name)

        assert config.project_name == "ml-pipeline"
        assert config.timezone == "UTC"
        assert config.symbols == ["SAMPLE-001"]
        assert config.enabled is True

    def test_env_path(self, config_file: str, monkeypatch: pytest.MonkeyPatch) -> None:
        """Test loading from CONFIG_PATH environment variable."""
        monkeypatch.setenv("CONFIG_PATH", config_file)
        config = load_config()
        assert config.project_name == "test-project"


class TestConfig:
    def test_config_dataclass_fields(self) -> None:
        """Test Config dataclass has all required fields."""
        config = Config(
            project_name="test",
            timezone="UTC",
            symbols=["SYMBOL-A"],
            enabled=True,
            schedule="0 * * * *",
            backfill_enabled=True,
            data_columns=["value"],
            technical_indicators={},
            time_features_enabled=True,
            lag_columns=["value"],
            lag_periods=[1],
            return_periods=[1],
            return_column="value",
            target_horizons=[1],
            target_column="value",
            dispersion_windows=[1, 24],
            clickhouse_host="localhost",
            clickhouse_port=8123,
            clickhouse_database="test",
            kafka_brokers="localhost:9092",
            kafka_topic_raw="raw",
            kafka_topic_features="features",
            train_start="2024-01-01",
            train_end="2024-06-01",
            validation_start="2024-06-01",
            validation_end="2024-07-01",
        )
        assert config.project_name == "test"
        assert config.clickhouse_port == 8123
