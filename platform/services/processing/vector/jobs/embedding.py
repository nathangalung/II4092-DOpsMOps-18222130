"""
Text Embedding Job using Qdrant vector database.
Generates embeddings from text data and stores in Qdrant for vector search.
Supports any text-based features (documents, descriptions, content, etc.).

Infrastructure dependencies:
  - Qdrant (v1.13.2): Purpose-built vector DB with built-in HNSW indexing
  - ClickHouse: Source for text data, archival for aggregated features
  - Valkey: Feature cache for online serving (aggregated embeddings; RESP)
"""

import logging
import os
from datetime import UTC, datetime, timedelta

import clickhouse_connect
import numpy as np
import redis
from prometheus_client import Counter, Gauge, Histogram
from qdrant_client import QdrantClient
from qdrant_client.models import (
    Distance,
    HnswConfigDiff,
    PointStruct,
    VectorParams,
)
from sentence_transformers import SentenceTransformer

from config import Config

logger = logging.getLogger(__name__)

DATA_TABLE = os.getenv("VECTOR_DATA_TABLE", os.getenv("DATA_TABLE", "text_data"))
FEATURES_TABLE = os.getenv(
    "VECTOR_FEATURES_TABLE", os.getenv("FEATURES_TABLE", "text_features")
)
TEXT_COLUMN = os.getenv("TEXT_COLUMN", "raw_data")

# Prometheus metrics
EMBEDDINGS_GENERATED = Counter(
    "vector_embeddings_generated_total",
    "Total embeddings generated",
    ["symbol"],
)
EMBEDDING_LATENCY = Histogram(
    "vector_embedding_latency_seconds",
    "Embedding generation latency",
    buckets=[0.01, 0.05, 0.1, 0.5, 1.0, 2.0, 5.0],
)
QDRANT_SEARCH_LATENCY = Histogram(
    "vector_qdrant_search_latency_seconds",
    "Qdrant vector search latency",
    buckets=[0.001, 0.005, 0.01, 0.05, 0.1],
)
INDEX_SIZE = Gauge(
    "vector_index_size",
    "Number of vectors in Qdrant collection",
)

# Distance metric mapping
DISTANCE_MAP = {
    "Cosine": Distance.COSINE,
    "Euclid": Distance.EUCLID,
    "Dot": Distance.DOT,
}


class TextEmbeddingJob:
    """
    Generates embeddings for text data using sentence-transformers.
    Stores embeddings in Qdrant for fast similarity search.
    """

    def __init__(self, config: Config) -> None:
        self.config = config
        self.clickhouse = None
        self.qdrant = None
        self.valkey = None
        self.model = None

    def connect(self) -> None:
        """Connect to ClickHouse, Qdrant, Valkey, and load embedding model."""
        # ClickHouse for reading text data
        self.clickhouse = clickhouse_connect.get_client(
            host=self.config.clickhouse_host,
            port=self.config.clickhouse_port,
            database=self.config.clickhouse_database,
            username=self.config.clickhouse_user,
            password=self.config.clickhouse_password,
        )
        logger.info("Connected to ClickHouse: %s", self.config.clickhouse_host)

        # Qdrant for vector storage and search. api_key may be empty in
        # dev (no auth) but must be passed through when set — Qdrant's
        # Python client treats empty string the same as missing.
        self.qdrant = QdrantClient(
            url=self.config.qdrant_url,
            api_key=self.config.qdrant_api_key or None,
        )
        logger.info("Connected to Qdrant: %s", self.config.qdrant_url)

        # Valkey for feature cache (aggregated scores for online serving; RESP).
        # Same empty-string-means-no-auth convention as Qdrant above.
        self.valkey = redis.Redis(
            host=self.config.redis_host,
            port=self.config.redis_port,
            password=self.config.redis_password or None,
            decode_responses=False,
        )
        logger.info("Connected to Valkey: %s", self.config.redis_host)

        # Load sentence-transformers model (BERT-based)
        model_name = (
            self.config.embedding_model or "sentence-transformers/all-mpnet-base-v2"
        )
        logger.info("Loading embedding model: %s", model_name)
        self.model = SentenceTransformer(model_name)
        self.embedding_dim = self.model.get_sentence_embedding_dimension()
        logger.info("Model loaded, dimension: %d", self.embedding_dim)

        # Ensure Qdrant collection exists
        self._ensure_collection()

    def _ensure_collection(self) -> None:
        """Create Qdrant collection if it doesn't exist."""
        collection_name = self.config.qdrant_collection
        collections = [c.name for c in self.qdrant.get_collections().collections]

        if collection_name in collections:
            logger.info("Collection %s already exists", collection_name)
            return

        distance = DISTANCE_MAP.get(self.config.distance_metric, Distance.COSINE)

        self.qdrant.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(
                size=self.embedding_dim,
                distance=distance,
                hnsw_config=HnswConfigDiff(
                    m=self.config.hnsw_m,
                    ef_construct=self.config.hnsw_ef_construct,
                ),
            ),
        )
        logger.info("Created Qdrant collection: %s", collection_name)

    def run(
        self, start_time: datetime | None = None, end_time: datetime | None = None
    ) -> None:
        """Generate embeddings for text data."""
        if self.clickhouse is None:
            self.connect()

        if end_time is None:
            end_time = datetime.now(tz=UTC)
        if start_time is None:
            start_time = end_time - timedelta(hours=self.config.embedding_window_hours)

        logger.info("Processing text data from %s to %s", start_time, end_time)

        for symbol in self.config.symbols:
            try:
                self._process_symbol(symbol, start_time, end_time)
            except Exception as e:
                logger.error("Error processing %s: %s", symbol, e)

        # Update index size metric
        try:
            info = self.qdrant.get_collection(self.config.qdrant_collection)
            INDEX_SIZE.set(info.points_count)
        except Exception:
            pass

    def _process_symbol(
        self, symbol: str, start_time: datetime, end_time: datetime
    ) -> None:
        """Process embeddings for a single symbol."""
        # Load text data from ClickHouse
        query = f"""
            SELECT
                symbol,
                timestamp,
                source,
                score,
                label,
                {TEXT_COLUMN}
            FROM {DATA_TABLE}
            WHERE symbol = '{symbol}'
              AND timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
              AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
              AND length({TEXT_COLUMN}) >= {self.config.min_text_length}
            ORDER BY timestamp ASC
        """

        result = self.clickhouse.query(query)
        if not result.result_rows:
            logger.info("No text data for %s", symbol)
            return

        rows = list(result.result_rows)
        logger.info("Processing %d text records for %s", len(rows), symbol)

        # Process in batches
        batch_size = self.config.embedding_batch_size
        embeddings_stored = 0

        for i in range(0, len(rows), batch_size):
            batch = rows[i : i + batch_size]
            texts = [row[5] for row in batch]  # text column

            # Generate embeddings
            with EMBEDDING_LATENCY.time():
                embeddings = self.model.encode(
                    texts,
                    batch_size=batch_size,
                    show_progress_bar=False,
                    normalize_embeddings=True,
                )

            # Store in Qdrant
            points = []
            for row, embedding in zip(batch, embeddings, strict=False):
                symbol_val, timestamp, source, score, label, text = row

                point_id = int(timestamp.timestamp() * 1000) + hash(source) % 1000
                # Ensure positive ID (Qdrant requires unsigned int)
                point_id = abs(point_id) % (2**63)

                points.append(
                    PointStruct(
                        id=point_id,
                        vector=embedding.tolist(),
                        payload={
                            "symbol": symbol_val,
                            "source": source,
                            "text": text[:500] if text else "",
                            "timestamp": timestamp.isoformat(),
                            "timestamp_unix": timestamp.timestamp(),
                            "score": float(score) if score else 0.0,
                            "label": label or "neutral",
                        },
                    )
                )
                embeddings_stored += 1
                EMBEDDINGS_GENERATED.labels(symbol=symbol_val).inc()

            # Upsert batch to Qdrant
            if points:
                self.qdrant.upsert(
                    collection_name=self.config.qdrant_collection,
                    points=points,
                )

        logger.info("Stored %d embeddings for %s", embeddings_stored, symbol)

        # Write aggregated features to ClickHouse + Valkey
        self._write_aggregated_features(symbol, start_time, end_time)

    def _write_aggregated_features(
        self, symbol: str, start_time: datetime, end_time: datetime
    ) -> None:
        """Write aggregated features to ClickHouse for training."""
        windows = [1, 6, 24]  # hours

        for window_hours in windows:
            window_start = end_time - timedelta(hours=window_hours)

            query = f"""
                SELECT
                    count(*) as record_count,
                    avg(score) as avg_score,
                    stddevPop(score) as score_std,
                    sumIf(1, label = 'positive') as positive_count,
                    sumIf(1, label = 'negative') as negative_count
                FROM {DATA_TABLE}
                WHERE symbol = '{symbol}'
                  AND timestamp >= '{window_start.strftime("%Y-%m-%d %H:%M:%S")}'
                  AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
            """

            result = self.clickhouse.query(query)
            if result.result_rows and result.result_rows[0][0] > 0:
                row = result.result_rows[0]
                record_count, avg_score, score_std, pos_count, neg_count = row

                prev_start = window_start - timedelta(hours=window_hours)
                prev_query = f"""
                    SELECT avg(score) as prev_score
                    FROM {DATA_TABLE}
                    WHERE symbol = '{symbol}'
                      AND timestamp >= '{prev_start.strftime("%Y-%m-%d %H:%M:%S")}'
                      AND timestamp < '{window_start.strftime("%Y-%m-%d %H:%M:%S")}'
                """
                prev_result = self.clickhouse.query(prev_query)
                prev_score = (
                    prev_result.result_rows[0][0] if prev_result.result_rows else 0
                )

                score_momentum = (avg_score or 0) - (prev_score or 0)

                self._store_aggregated_features(
                    symbol=symbol,
                    timestamp=end_time,
                    window_hours=window_hours,
                    record_count=record_count,
                    avg_score=avg_score or 0,
                    score_std=score_std or 0,
                    positive_ratio=(
                        pos_count / record_count if record_count > 0 else 0.5
                    ),
                    score_momentum=score_momentum,
                )

    def _store_aggregated_features(
        self,
        symbol: str,
        timestamp: datetime,
        window_hours: int,
        record_count: int,
        avg_score: float,
        score_std: float,
        positive_ratio: float,
        score_momentum: float,
    ) -> None:
        """Store aggregated features in ClickHouse and Valkey."""
        # Insert to ClickHouse for offline training
        insert_query = f"""
            INSERT INTO {FEATURES_TABLE}
            (symbol, timestamp, window_hours, record_count, avg_score,
             score_std, positive_ratio, score_momentum)
            VALUES
            ('{symbol}', '{timestamp.strftime("%Y-%m-%d %H:%M:%S")}', {window_hours},
             {record_count}, {avg_score}, {score_std}, {positive_ratio}, {score_momentum})
        """
        try:
            self.clickhouse.command(insert_query)
        except Exception as e:
            logger.warning("Failed to insert features: %s", e)

        # Update Valkey for online serving (feature cache)
        valkey_key = f"feast:text:{symbol}:{window_hours}h"
        self.valkey.hset(
            valkey_key,
            mapping={
                "symbol": symbol,
                "window_hours": window_hours,
                "record_count": record_count,
                "avg_score": avg_score,
                "score_std": score_std,
                "positive_ratio": positive_ratio,
                "score_momentum": score_momentum,
                "updated_at": timestamp.timestamp(),
            },
        )
        self.valkey.expire(valkey_key, 3600 * 24)  # 24 hours TTL

    def search_similar(
        self,
        query_text: str,
        symbol: str | None = None,
        top_k: int = 10,
    ) -> list:
        """
        Search for similar text using vector similarity.

        Args:
            query_text: Text to search for similar content
            symbol: Optional symbol filter
            top_k: Number of results to return

        Returns:
            List of similar records
        """
        if self.model is None:
            self.connect()

        # Generate embedding for query
        with EMBEDDING_LATENCY.time():
            query_embedding = self.model.encode(
                query_text,
                normalize_embeddings=True,
            ).astype(np.float32)

        # Build Qdrant filter
        query_filter = None
        if symbol:
            from qdrant_client.models import FieldCondition, Filter, MatchValue

            query_filter = Filter(
                must=[FieldCondition(key="symbol", match=MatchValue(value=symbol))]
            )

        # Execute search
        with QDRANT_SEARCH_LATENCY.time():
            results = self.qdrant.query_points(
                collection_name=self.config.qdrant_collection,
                query=query_embedding.tolist(),
                query_filter=query_filter,
                limit=top_k,
                with_payload=True,
            )

        # Format results
        output = []
        for point in results.points:
            payload = point.payload
            output.append(
                {
                    "id": point.id,
                    "symbol": payload.get("symbol", ""),
                    "source": payload.get("source", ""),
                    "text": payload.get("text", ""),
                    "timestamp": payload.get("timestamp", ""),
                    "score": payload.get("score", 0.0),
                    "similarity": point.score,
                }
            )

        return output

    def get_aggregated_embedding(
        self, symbol: str, window_hours: int = 24
    ) -> np.ndarray | None:
        """
        Get aggregated embedding for a symbol (mean of recent embeddings).
        Used as input feature for prediction models.
        """
        from qdrant_client.models import FieldCondition, Filter, MatchValue, Range

        end_time = datetime.now(tz=UTC)
        start_time = end_time - timedelta(hours=window_hours)

        # Query Qdrant for recent embeddings
        results = self.qdrant.query_points(
            collection_name=self.config.qdrant_collection,
            query=[0.0] * self.config.embedding_dim,  # Dummy query
            query_filter=Filter(
                must=[
                    FieldCondition(key="symbol", match=MatchValue(value=symbol)),
                    FieldCondition(
                        key="timestamp_unix",
                        range=Range(
                            gte=start_time.timestamp(), lte=end_time.timestamp()
                        ),
                    ),
                ]
            ),
            limit=1000,
            with_vectors=True,
        )

        if not results.points:
            return None

        embeddings = [np.array(p.vector) for p in results.points]
        return np.mean(embeddings, axis=0)

    def close(self) -> None:
        """Close connections."""
        if self.clickhouse:
            self.clickhouse.close()
            self.clickhouse = None
        if self.qdrant:
            self.qdrant.close()
            self.qdrant = None
        if self.valkey:
            self.valkey.close()
            self.valkey = None


class EmbeddingJob(TextEmbeddingJob):
    """Alias for backward compatibility."""

    pass
