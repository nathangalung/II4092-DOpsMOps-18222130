"""
Configuration loader for batch processing service.
Reads from config.yaml if available, falls back to environment variables.

This is a GENERIC configuration loader — no domain-specific defaults.
Use-cases provide their own config.yaml with domain-specific values.
"""

import os
from dataclasses import dataclass, field
from typing import Any

import yaml


def _csv(env: str, default: str) -> list[str]:
    """Parse comma-separated env var into list."""
    return [s.strip() for s in os.getenv(env, default).split(",") if s.strip()]


def _csv_int(env: str, default: str) -> list[int]:
    """Parse comma-separated env var into list of ints."""
    return [int(s.strip()) for s in os.getenv(env, default).split(",") if s.strip()]


@dataclass
class Config:
    """Batch processing configuration — generic, domain-agnostic."""

    # Project settings
    project_name: str = "ml-pipeline"
    timezone: str = "UTC"
    symbols: list[str] = field(default_factory=lambda: ["SAMPLE-001"])

    # Processing settings
    enabled: bool = True
    schedule: str = "0 * * * *"
    backfill_enabled: bool = True

    # Feature settings — all configurable, no hardcoded indicators
    data_columns: list[str] = field(default_factory=lambda: ["value"])
    technical_indicators: dict[str, Any] = field(default_factory=dict)
    time_features_enabled: bool = True
    lag_columns: list[str] = field(default_factory=lambda: ["value"])
    lag_periods: list[int] = field(default_factory=lambda: [1, 6, 12, 24])
    return_periods: list[int] = field(default_factory=lambda: [1, 6, 12, 24])
    return_column: str = "value"
    target_horizons: list[int] = field(default_factory=lambda: [1])
    target_column: str = "value"
    dispersion_windows: list[int] = field(default_factory=lambda: [1, 24])

    # Infrastructure
    clickhouse_host: str = "localhost"
    clickhouse_port: int = 8123
    clickhouse_database: str = "features"
    kafka_brokers: str = "localhost:9092"
    kafka_topic_raw: str = "raw"
    kafka_topic_features: str = "features"

    # Data splits
    train_start: str = "2024-12-01T00:00:00"
    train_end: str = "2025-12-01T00:00:00"
    validation_start: str = "2025-12-01T00:00:00"
    validation_end: str = "2025-12-21T00:00:00"


def load_config(path: str | None = None) -> Config:
    """Load configuration from YAML file if available, then env var overrides."""
    config = Config()

    # Try to load from YAML file
    if path is None:
        path = os.getenv("CONFIG_PATH", "/app/config/config.yaml")

    if os.path.exists(path):
        with open(path) as f:
            data = yaml.safe_load(f) or {}

        project = data.get("project", {})
        source = data.get("data_source", {})
        services = data.get("services", {})
        features = data.get("features", {})
        infra = data.get("infrastructure", {})
        splits = data.get("data_splits", {})

        # Project
        config.project_name = project.get("name", config.project_name)
        config.timezone = project.get("timezone", config.timezone)
        config.symbols = source.get("api", {}).get("symbols", config.symbols)

        # Processing
        batch = services.get("processing", {}).get("batch", {})
        config.enabled = batch.get("enabled", config.enabled)
        config.schedule = batch.get("schedule", config.schedule)
        config.backfill_enabled = batch.get("backfill_enabled", config.backfill_enabled)

        # Features
        config.data_columns = features.get("data_columns", config.data_columns)
        config.technical_indicators = features.get(
            "technical_indicators", config.technical_indicators
        )
        config.time_features_enabled = features.get(
            "time_features_enabled", config.time_features_enabled
        )
        config.lag_columns = features.get("lag_columns", config.lag_columns)
        config.lag_periods = features.get("lag_periods", config.lag_periods)
        config.return_periods = features.get("return_periods", config.return_periods)
        config.return_column = features.get("return_column", config.return_column)
        config.target_horizons = features.get("target_horizons", config.target_horizons)
        config.target_column = features.get("target_column", config.target_column)
        config.dispersion_windows = features.get(
            "dispersion_windows", config.dispersion_windows
        )

        # Infrastructure
        config.clickhouse_host = infra.get("clickhouse", {}).get(
            "host", config.clickhouse_host
        )
        config.clickhouse_port = infra.get("clickhouse", {}).get(
            "port", config.clickhouse_port
        )
        config.clickhouse_database = infra.get("clickhouse", {}).get(
            "database", config.clickhouse_database
        )
        config.kafka_brokers = infra.get("kafka", {}).get(
            "brokers", config.kafka_brokers
        )
        config.kafka_topic_raw = (
            infra.get("kafka", {}).get("topics", {}).get("raw", config.kafka_topic_raw)
        )
        config.kafka_topic_features = (
            infra.get("kafka", {})
            .get("topics", {})
            .get("features", config.kafka_topic_features)
        )

        # Splits
        config.train_start = splits.get("train", {}).get("start", config.train_start)
        config.train_end = splits.get("train", {}).get("end", config.train_end)
        config.validation_start = splits.get("validation", {}).get(
            "start", config.validation_start
        )
        config.validation_end = splits.get("validation", {}).get(
            "end", config.validation_end
        )

    # Environment variable overrides (highest priority)
    # Symbols — from VALID_SYMBOLS (quality config) or SYMBOLS
    if os.getenv("VALID_SYMBOLS"):
        config.symbols = _csv("VALID_SYMBOLS", "")
    elif os.getenv("SYMBOLS"):
        config.symbols = _csv("SYMBOLS", "")

    # Data columns — strip symbol/timestamp (already prepended by query builder)
    if os.getenv("DATA_COLUMNS"):
        all_cols = _csv("DATA_COLUMNS", "")
        config.data_columns = [c for c in all_cols if c not in ("symbol", "timestamp")]

    # Target/return column
    if os.getenv("TARGET_COLUMN"):
        config.target_column = os.getenv("TARGET_COLUMN")
        config.return_column = os.getenv("TARGET_COLUMN")

    # Infrastructure
    config.clickhouse_host = os.getenv("CLICKHOUSE_HOST", config.clickhouse_host)
    config.clickhouse_port = int(
        os.getenv("CLICKHOUSE_PORT", str(config.clickhouse_port))
    )
    config.clickhouse_database = os.getenv("CLICKHOUSE_DB", config.clickhouse_database)
    config.kafka_brokers = os.getenv("KAFKA_BROKERS", config.kafka_brokers)
    config.kafka_topic_raw = os.getenv("KAFKA_TOPIC", config.kafka_topic_raw)
    config.kafka_topic_features = os.getenv(
        "KAFKA_FEATURES_TOPIC", config.kafka_topic_features
    )
    config.train_start = os.getenv("START_DATE", config.train_start)
    config.train_end = os.getenv("END_DATE", config.train_end)

    return config
