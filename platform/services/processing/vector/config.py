"""
Configuration loader for vector processing service.
Reads from config.yaml and environment variables for settings.
Supports BERT-based sentence embeddings with Qdrant vector search.
"""

import os
from dataclasses import dataclass, field

import yaml


@dataclass
class Config:
    """Vector processing configuration for embeddings."""

    # Project settings
    project_name: str = "ml-pipeline"
    timezone: str = "UTC"
    symbols: list[str] = field(default_factory=lambda: ["SAMPLE-001", "SAMPLE-002"])

    # Processing settings
    enabled: bool = True

    # Embedding model settings (BERT-based per thesis requirements)
    embedding_model: str = "sentence-transformers/all-mpnet-base-v2"
    embedding_dim: int = 768
    max_sequence_length: int = 512
    embedding_batch_size: int = 32
    embedding_window_hours: int = 24
    min_text_length: int = 50

    # Qdrant vector store parameters
    qdrant_url: str = "http://localhost:6333"
    qdrant_grpc_url: str = "localhost:6334"
    qdrant_collection: str = os.getenv("VECTOR_COLLECTION", "embeddings")
    distance_metric: str = "Cosine"
    hnsw_m: int = 16
    hnsw_ef_construct: int = 200

    # Similarity search
    similarity_top_k: int = 10
    similarity_threshold: float = 0.8
    similarity_return_field: str = "return"

    # Infrastructure (Valkey for feature cache, ClickHouse for offline store).
    # Struct fields keep the `redis_*` prefix because the wire protocol is RESP
    # (the redis-py library speaks it directly to a Valkey server).
    clickhouse_host: str = "localhost"
    clickhouse_port: int = 8123
    clickhouse_database: str = "features"
    redis_host: str = "localhost"
    redis_port: int = 6379
    # Auth credentials — populated from environment only (pipeline-secrets
    # Secret injects VALKEY_PASSWORD and QDRANT_API_KEY into every pod).
    # Never set a YAML default: the YAML file is baked into the image and
    # must not carry runtime secrets.
    redis_password: str = ""
    qdrant_api_key: str = ""


def load_config(path: str | None = None) -> Config:
    """
    Load configuration from YAML file and environment variables.
    Environment variables take precedence over YAML settings.
    """
    config = Config()

    # Try to load from YAML file
    if path is None:
        path = os.getenv("CONFIG_PATH", "/app/config/config.yaml")

    if os.path.exists(path):
        with open(path) as f:
            data = yaml.safe_load(f)

        # Extract relevant sections
        project = data.get("project", {})
        source = data.get("data_source", {})
        services = data.get("services", {})
        infra = data.get("infrastructure", {})

        vector = services.get("processing", {}).get("vector", {})

        # Project settings
        config.project_name = project.get("name", config.project_name)
        config.timezone = project.get("timezone", config.timezone)
        config.symbols = source.get("api", {}).get("symbols", config.symbols)

        # Vector/embedding settings
        config.enabled = vector.get("enabled", config.enabled)

        model_config = vector.get("model", {})
        config.embedding_model = model_config.get("name", config.embedding_model)
        config.embedding_dim = model_config.get("dimension", config.embedding_dim)
        config.max_sequence_length = model_config.get(
            "max_sequence_length", config.max_sequence_length
        )
        config.embedding_batch_size = model_config.get(
            "batch_size", config.embedding_batch_size
        )

        # Qdrant settings
        qdrant_config = vector.get("qdrant", {})
        config.qdrant_url = qdrant_config.get("url", config.qdrant_url)
        config.qdrant_grpc_url = qdrant_config.get("grpc_url", config.qdrant_grpc_url)
        config.qdrant_collection = qdrant_config.get(
            "collection", config.qdrant_collection
        )
        config.distance_metric = qdrant_config.get(
            "distance_metric", config.distance_metric
        )
        config.hnsw_m = qdrant_config.get("hnsw_m", config.hnsw_m)
        config.hnsw_ef_construct = qdrant_config.get(
            "hnsw_ef_construct", config.hnsw_ef_construct
        )

        processing = vector.get("processing", {})
        config.embedding_window_hours = processing.get(
            "window_hours", config.embedding_window_hours
        )
        config.min_text_length = processing.get(
            "min_text_length", config.min_text_length
        )
        config.similarity_threshold = processing.get(
            "similarity_threshold", config.similarity_threshold
        )
        config.similarity_return_field = processing.get(
            "return_field", config.similarity_return_field
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
        config.redis_host = infra.get("redis", {}).get("host", config.redis_host)
        config.redis_port = infra.get("redis", {}).get("port", config.redis_port)

    # Environment variable overrides (highest priority)
    config.enabled = os.getenv("VECTOR_ENABLED", str(config.enabled)).lower() == "true"
    config.embedding_model = os.getenv("EMBEDDING_MODEL", config.embedding_model)
    config.embedding_dim = int(os.getenv("EMBEDDING_DIM", str(config.embedding_dim)))
    config.embedding_window_hours = int(
        os.getenv("EMBEDDING_WINDOW_HOURS", str(config.embedding_window_hours))
    )
    config.min_text_length = int(
        os.getenv("MIN_TEXT_LENGTH", str(config.min_text_length))
    )

    # Qdrant env overrides
    config.qdrant_url = os.getenv("QDRANT_URL", config.qdrant_url)
    config.qdrant_grpc_url = os.getenv("QDRANT_GRPC_URL", config.qdrant_grpc_url)
    config.qdrant_collection = os.getenv("VECTOR_COLLECTION", config.qdrant_collection)

    config.similarity_return_field = os.getenv(
        "SIMILARITY_RETURN_FIELD", config.similarity_return_field
    )

    # Infrastructure env overrides
    config.clickhouse_host = os.getenv("CLICKHOUSE_HOST", config.clickhouse_host)
    config.clickhouse_port = int(
        os.getenv("CLICKHOUSE_PORT", str(config.clickhouse_port))
    )
    config.clickhouse_database = os.getenv(
        "CLICKHOUSE_DATABASE", config.clickhouse_database
    )
    config.redis_host = os.getenv("VALKEY_HOST", config.redis_host)
    config.redis_port = int(os.getenv("VALKEY_PORT", str(config.redis_port)))
    config.redis_password = os.getenv("VALKEY_PASSWORD", config.redis_password)
    config.qdrant_api_key = os.getenv("QDRANT_API_KEY", config.qdrant_api_key)

    return config
