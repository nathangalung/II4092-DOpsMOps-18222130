#!/usr/bin/env -S uv run python
"""Feature Store Service - Redis/ClickHouse Integration"""

import logging
import os
import json
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Optional, Any

import redis
import clickhouse_connect
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FeatureStoreConfig:
    """Feature store configuration"""

    def __init__(self):
        self.valkey_host = os.getenv("VALKEY_HOST", "valkey.storage.svc.cluster.local")
        self.valkey_port = int(os.getenv("VALKEY_PORT", "6379"))
        self.clickhouse_host = os.getenv(
            "CLICKHOUSE_HOST", "clickhouse-platform.storage.svc.cluster.local"
        )
        self.clickhouse_port = int(os.getenv("CLICKHOUSE_PORT", "8123"))
        self.clickhouse_db = os.getenv("CLICKHOUSE_DB", "features")
        self.ttl_seconds = int(os.getenv("FEATURE_TTL", "3600"))


class OnlineFeatureStore:
    """Valkey-based online feature store for low-latency retrieval"""

    def __init__(self, config: FeatureStoreConfig = None):
        self.config = config or FeatureStoreConfig()
        self.redis = redis.Redis(
            host=self.config.valkey_host,
            port=self.config.valkey_port,
            decode_responses=True,
        )

    def set_features(
        self,
        entity_type: str,
        entity_id: str,
        features: Dict[str, float],
        ttl: int = None,
    ):
        """Set features for entity"""
        key = f"features:{entity_type}:{entity_id}"

        pipe = self.redis.pipeline()
        pipe.hset(key, mapping={k: str(v) for k, v in features.items()})
        pipe.hset(key, "_updated_at", datetime.now(timezone.utc).isoformat())
        pipe.expire(key, ttl or self.config.ttl_seconds)
        pipe.execute()

        logger.debug(f"Set {len(features)} features for {key}")

    def get_features(
        self, entity_type: str, entity_id: str, feature_names: List[str] = None
    ) -> Dict[str, float]:
        """Get features for entity"""
        key = f"features:{entity_type}:{entity_id}"

        if feature_names:
            values = self.redis.hmget(key, feature_names)
            features = {
                name: float(val) if val else None
                for name, val in zip(feature_names, values)
            }
        else:
            raw = self.redis.hgetall(key)
            features = {}
            for k, v in raw.items():
                if k.startswith("_"):
                    continue
                try:
                    features[k] = float(v)
                except ValueError:
                    pass

        return features

    def get_batch_features(
        self, entity_type: str, entity_ids: List[str], feature_names: List[str] = None
    ) -> Dict[str, Dict]:
        """Get features for multiple entities"""
        results = {}

        pipe = self.redis.pipeline()
        keys = [f"features:{entity_type}:{eid}" for eid in entity_ids]

        for key in keys:
            if feature_names:
                pipe.hmget(key, feature_names)
            else:
                pipe.hgetall(key)

        responses = pipe.execute()

        for entity_id, response in zip(entity_ids, responses):
            if feature_names:
                results[entity_id] = {
                    name: float(val) if val else None
                    for name, val in zip(feature_names, response)
                }
            else:
                results[entity_id] = {
                    k: float(v)
                    for k, v in response.items()
                    if not k.startswith("_") and v
                }

        return results

    def append_sequence(
        self,
        entity_type: str,
        entity_id: str,
        features: Dict[str, float],
        max_length: int = 1000,
    ):
        """Append to feature sequence (for LSTM models)"""
        key = f"sequence:{entity_type}:{entity_id}"

        features["_timestamp"] = datetime.now(timezone.utc).timestamp()

        self.redis.rpush(key, json.dumps(features))
        self.redis.ltrim(key, -max_length, -1)

    def get_sequence(
        self, entity_type: str, entity_id: str, length: int = 60
    ) -> List[Dict]:
        """Get feature sequence"""
        key = f"sequence:{entity_type}:{entity_id}"

        raw = self.redis.lrange(key, -length, -1)

        return [json.loads(item) for item in raw]

    def delete_features(self, entity_type: str, entity_id: str):
        """Delete features for entity"""
        key = f"features:{entity_type}:{entity_id}"
        self.redis.delete(key)


class OfflineFeatureStore:
    """ClickHouse-based offline feature store for historical data"""

    def __init__(self, config: FeatureStoreConfig = None):
        self.config = config or FeatureStoreConfig()
        self._client = None

    @property
    def client(self):
        """Lazy client initialization"""
        if self._client is None:
            self._client = clickhouse_connect.get_client(
                host=self.config.clickhouse_host,
                port=self.config.clickhouse_port,
                database=self.config.clickhouse_db,
            )
        return self._client

    def create_feature_table(self, entity_type: str, feature_schema: Dict[str, str]):
        """Create feature table in ClickHouse"""
        columns = ["entity_id String", "timestamp DateTime64(3)"]

        type_map = {
            "float": "Float64",
            "int": "Int64",
            "string": "String",
            "bool": "UInt8",
        }

        for name, dtype in feature_schema.items():
            ch_type = type_map.get(dtype, "Float64")
            columns.append(f"{name} {ch_type}")

        query = f"""
        CREATE TABLE IF NOT EXISTS {entity_type}_features (
            {', '.join(columns)}
        ) ENGINE = MergeTree()
        ORDER BY (entity_id, timestamp)
        TTL timestamp + INTERVAL 90 DAY
        """

        self.client.command(query)
        logger.info(f"Created table {entity_type}_features")

    def write_features(
        self,
        entity_type: str,
        entity_id: str,
        features: Dict[str, Any],
        timestamp: datetime = None,
    ):
        """Write features to ClickHouse"""
        timestamp = timestamp or datetime.now(timezone.utc)

        columns = ["entity_id", "timestamp"] + list(features.keys())
        values = [[entity_id, timestamp] + list(features.values())]

        self.client.insert(f"{entity_type}_features", values, column_names=columns)

    def write_batch_features(self, entity_type: str, records: List[Dict[str, Any]]):
        """Write batch features to ClickHouse"""
        if not records:
            return

        columns = list(records[0].keys())
        values = [[r[c] for c in columns] for r in records]

        self.client.insert(f"{entity_type}_features", values, column_names=columns)

        logger.info(f"Wrote {len(records)} records to {entity_type}_features")

    def get_historical_features(
        self,
        entity_type: str,
        entity_id: str,
        start_time: datetime,
        end_time: datetime,
        feature_names: List[str] = None,
    ) -> List[Dict]:
        """Get historical features for entity"""
        columns = feature_names or ["*"]

        query = f"""
        SELECT {', '.join(columns)}, timestamp
        FROM {entity_type}_features
        WHERE entity_id = %(entity_id)s
          AND timestamp >= %(start_time)s
          AND timestamp <= %(end_time)s
        ORDER BY timestamp
        """

        result = self.client.query(
            query,
            parameters={
                "entity_id": entity_id,
                "start_time": start_time,
                "end_time": end_time,
            },
        )

        return result.named_results()

    def get_training_data(
        self,
        entity_type: str,
        entity_ids: List[str],
        start_time: datetime,
        end_time: datetime,
        feature_names: List[str],
    ) -> List[Dict]:
        """Get training data for multiple entities"""
        query = f"""
        SELECT entity_id, timestamp, {', '.join(feature_names)}
        FROM {entity_type}_features
        WHERE entity_id IN %(entity_ids)s
          AND timestamp >= %(start_time)s
          AND timestamp <= %(end_time)s
        ORDER BY entity_id, timestamp
        """

        result = self.client.query(
            query,
            parameters={
                "entity_ids": entity_ids,
                "start_time": start_time,
                "end_time": end_time,
            },
        )

        return result.named_results()

    def get_latest_features(self, entity_type: str, entity_id: str) -> Optional[Dict]:
        """Get latest features for entity"""
        query = f"""
        SELECT *
        FROM {entity_type}_features
        WHERE entity_id = %(entity_id)s
        ORDER BY timestamp DESC
        LIMIT 1
        """

        result = self.client.query(query, parameters={"entity_id": entity_id})

        rows = result.named_results()
        return rows[0] if rows else None


class FeatureStore:
    """Unified feature store with online/offline layers"""

    def __init__(self, config: FeatureStoreConfig = None):
        self.config = config or FeatureStoreConfig()
        self.online = OnlineFeatureStore(self.config)
        self.offline = OfflineFeatureStore(self.config)

    def materialize_features(
        self,
        entity_type: str,
        entity_id: str,
        features: Dict[str, float],
        timestamp: datetime = None,
    ):
        """Write to both online and offline stores"""
        self.online.set_features(entity_type, entity_id, features)

        self.offline.write_features(entity_type, entity_id, features, timestamp)

    def get_online_features(
        self, entity_type: str, entity_id: str, feature_names: List[str] = None
    ) -> Dict[str, float]:
        """Get features from online store"""
        return self.online.get_features(entity_type, entity_id, feature_names)

    def get_training_dataset(
        self,
        entity_type: str,
        entity_ids: List[str],
        start_time: datetime,
        end_time: datetime,
        feature_names: List[str],
    ) -> List[Dict]:
        """Get training dataset from offline store"""
        return self.offline.get_training_data(
            entity_type, entity_ids, start_time, end_time, feature_names
        )

    def sync_to_online(self, entity_type: str, entity_id: str):
        """Sync latest offline features to online store"""
        latest = self.offline.get_latest_features(entity_type, entity_id)

        if latest:
            features = {
                k: v for k, v in latest.items() if k not in ["entity_id", "timestamp"]
            }
            self.online.set_features(entity_type, entity_id, features)


def create_feature_tables():
    """Initialize feature tables"""
    store = FeatureStore()

    crypto_schema = {
        "price": "float",
        "volume": "float",
        "rsi": "float",
        "macd": "float",
        "bb_upper": "float",
        "bb_lower": "float",
        "sma_20": "float",
        "ema_20": "float",
        "volatility": "float",
        "momentum": "float",
    }

    stock_schema = {
        "open": "float",
        "high": "float",
        "low": "float",
        "close": "float",
        "volume": "float",
        "rsi": "float",
        "macd": "float",
        "macd_signal": "float",
        "bb_upper": "float",
        "bb_lower": "float",
        "sma_20": "float",
        "sma_50": "float",
        "ema_12": "float",
        "ema_26": "float",
    }

    store.offline.create_feature_table("crypto", crypto_schema)
    store.offline.create_feature_table("stock", stock_schema)

    logger.info("Feature tables initialized")


if __name__ == "__main__":
    create_feature_tables()
