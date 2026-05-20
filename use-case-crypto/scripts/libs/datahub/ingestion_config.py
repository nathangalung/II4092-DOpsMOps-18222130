#!/usr/bin/env -S uv run python
"""DataHub Metadata Ingestion Configuration"""

import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


DATAHUB_GMS_URL = os.getenv(
    "DATAHUB_GMS_URL", "http://datahub-gms.data-governance.svc.cluster.local:8080"
)


CRYPTO_DATASET_CONFIG = {
    "source": {
        "type": "kafka",
        "config": {
            "connection": {"bootstrap": "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092"},
            "topic_patterns": {"allow": ["crypto.*"]},
            "platform_instance": "platform-kafka",
        },
    },
    "sink": {"type": "datahub-rest", "config": {"server": DATAHUB_GMS_URL}},
}


STOCK_DATASET_CONFIG = {
    "source": {
        "type": "kafka",
        "config": {
            "connection": {"bootstrap": "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092"},
            "topic_patterns": {"allow": ["stock.*"]},
            "platform_instance": "platform-kafka",
        },
    },
    "sink": {"type": "datahub-rest", "config": {"server": DATAHUB_GMS_URL}},
}


CLICKHOUSE_CONFIG = {
    "source": {
        "type": "clickhouse",
        "config": {
            "host_port": "clickhouse-platform.storage.svc.cluster.local:8123",
            "database": "features",
            "username": "default",
            "include_tables": True,
            "include_views": True,
            "profiling": {"enabled": True},
        },
    },
    "sink": {"type": "datahub-rest", "config": {"server": DATAHUB_GMS_URL}},
}


MLFLOW_CONFIG = {
    "source": {
        "type": "mlflow",
        "config": {
            "tracking_uri": "http://mlflow.model-lifecycle.svc.cluster.local:5000",
            "model_name_separator": "_",
        },
    },
    "sink": {"type": "datahub-rest", "config": {"server": DATAHUB_GMS_URL}},
}


AIRFLOW_CONFIG = {
    "source": {
        "type": "airflow",
        "config": {
            "base_url": "http://airflow-webserver.data-processing.svc.cluster.local:8080",
            "disable_ssl_verification": True,
        },
    },
    "sink": {"type": "datahub-rest", "config": {"server": DATAHUB_GMS_URL}},
}


CRYPTO_FEATURE_DEFINITIONS = [
    {"name": "price", "type": "FLOAT", "description": "Current price"},
    {"name": "volume_24h", "type": "FLOAT", "description": "24-hour trading volume"},
    {"name": "rsi", "type": "FLOAT", "description": "Relative strength index"},
    {
        "name": "macd",
        "type": "FLOAT",
        "description": "Moving average convergence divergence",
    },
    {"name": "macd_signal", "type": "FLOAT", "description": "MACD signal line"},
    {"name": "bb_upper", "type": "FLOAT", "description": "Bollinger band upper"},
    {"name": "bb_lower", "type": "FLOAT", "description": "Bollinger band lower"},
    {"name": "sma_20", "type": "FLOAT", "description": "Simple moving average 20"},
    {"name": "ema_20", "type": "FLOAT", "description": "Exponential moving average 20"},
    {"name": "volatility", "type": "FLOAT", "description": "Price volatility"},
    {"name": "momentum", "type": "FLOAT", "description": "Price momentum"},
    {
        "name": "fear_greed_index",
        "type": "FLOAT",
        "description": "Market sentiment index",
    },
]


STOCK_FEATURE_DEFINITIONS = [
    {"name": "open", "type": "FLOAT", "description": "Opening price"},
    {"name": "high", "type": "FLOAT", "description": "Highest price"},
    {"name": "low", "type": "FLOAT", "description": "Lowest price"},
    {"name": "close", "type": "FLOAT", "description": "Closing price"},
    {"name": "volume", "type": "FLOAT", "description": "Trading volume"},
    {"name": "rsi", "type": "FLOAT", "description": "Relative strength index"},
    {"name": "macd", "type": "FLOAT", "description": "MACD indicator"},
    {"name": "macd_signal", "type": "FLOAT", "description": "MACD signal line"},
    {"name": "bb_upper", "type": "FLOAT", "description": "Bollinger upper band"},
    {"name": "bb_lower", "type": "FLOAT", "description": "Bollinger lower band"},
    {"name": "sma_20", "type": "FLOAT", "description": "20-day SMA"},
    {"name": "sma_50", "type": "FLOAT", "description": "50-day SMA"},
    {"name": "ema_12", "type": "FLOAT", "description": "12-day EMA"},
    {"name": "ema_26", "type": "FLOAT", "description": "26-day EMA"},
]


def get_all_configs() -> Dict:
    """Get all ingestion configurations"""
    return {
        "crypto_kafka": CRYPTO_DATASET_CONFIG,
        "stock_kafka": STOCK_DATASET_CONFIG,
        "clickhouse": CLICKHOUSE_CONFIG,
        "mlflow": MLFLOW_CONFIG,
        "airflow": AIRFLOW_CONFIG,
    }


def get_feature_definitions() -> Dict:
    """Get feature definitions"""
    return {"crypto": CRYPTO_FEATURE_DEFINITIONS, "stock": STOCK_FEATURE_DEFINITIONS}
