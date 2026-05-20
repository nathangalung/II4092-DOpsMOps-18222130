"""
Similarity search job for finding similar historical patterns.
Uses Qdrant vector database for fast similarity search.

Platform tool integration:
  - Qdrant (v1.13.2): Purpose-built vector DB with HNSW indexing
  - Embedding model: Reuses TextEmbeddingJob for vector generation
"""

import logging
from datetime import UTC, datetime

import numpy as np
from qdrant_client import QdrantClient
from qdrant_client.models import FieldCondition, Filter, MatchValue

from config import Config
from jobs.embedding import EmbeddingJob

logger = logging.getLogger(__name__)


class SimilaritySearchJob:
    """
    Searches for similar historical patterns using Qdrant vector similarity.
    Can be used for pattern-based prediction and analysis.
    """

    def __init__(self, config: Config) -> None:
        self.config = config
        self.qdrant = None
        self.embedding_job = EmbeddingJob(config)
        self._return_field = config.similarity_return_field

    def connect(self) -> None:
        """Connect to Qdrant."""
        self.qdrant = QdrantClient(
            url=self.config.qdrant_url,
            api_key=self.config.qdrant_api_key or None,
        )
        logger.info("Connected to Qdrant: %s", self.config.qdrant_url)

    def find_similar_patterns(
        self,
        symbol: str,
        query_embedding: np.ndarray,
        top_k: int | None = None,
    ) -> list[dict]:
        """
        Find similar historical patterns for a given embedding.

        Args:
            symbol: Symbol to search patterns for
            query_embedding: Query embedding vector
            top_k: Number of similar patterns to return

        Returns:
            List of similar patterns with metadata
        """
        if self.qdrant is None:
            self.connect()

        if top_k is None:
            top_k = self.config.similarity_top_k

        query_vector = query_embedding.astype(np.float32).tolist()

        query_filter = Filter(
            must=[FieldCondition(key="symbol", match=MatchValue(value=symbol))]
        )

        results = self.qdrant.query_points(
            collection_name=self.config.qdrant_collection,
            query=query_vector,
            query_filter=query_filter,
            limit=top_k,
            with_payload=True,
        )

        similar_patterns = []
        for point in results.points:
            payload = point.payload
            pattern = {
                "id": point.id,
                "symbol": payload.get("symbol", ""),
                "timestamp": datetime.fromtimestamp(
                    float(payload.get("timestamp_unix", 0)), tz=UTC
                ),
                "value": float(payload.get("value", 0)),
                "return": float(payload.get(self._return_field, 0)),
                "similarity_score": point.score,
            }
            similar_patterns.append(pattern)

        return similar_patterns

    def find_similar_to_current(self, symbol: str, window_data: list) -> list[dict]:
        """
        Find patterns similar to current conditions.

        Args:
            symbol: Symbol to analyze
            window_data: Recent window data for embedding computation

        Returns:
            List of similar historical patterns
        """
        embedding = self.embedding_job._compute_embedding(window_data)
        return self.find_similar_patterns(symbol, embedding)

    def predict_from_similar(
        self,
        symbol: str,
        query_embedding: np.ndarray,
        horizon: str = "24h",
    ) -> dict:
        """
        Make prediction based on similar historical patterns.

        Args:
            symbol: Symbol to predict
            query_embedding: Current pattern embedding
            horizon: Prediction horizon

        Returns:
            Prediction with confidence
        """
        similar = self.find_similar_patterns(symbol, query_embedding)

        if not similar:
            return {
                "prediction": 0,
                "confidence": 0,
                "num_patterns": 0,
            }

        # Weight returns by similarity score
        total_weight = 0
        weighted_return = 0

        for pattern in similar:
            weight = pattern["similarity_score"]
            weighted_return += pattern["return"] * weight
            total_weight += weight

        predicted_return = weighted_return / total_weight if total_weight > 0 else 0

        # Direction prediction
        up_count = sum(1 for p in similar if p["return"] > 0)
        direction = 1 if up_count > len(similar) / 2 else -1

        # Confidence based on agreement and similarity
        agreement = max(up_count, len(similar) - up_count) / len(similar)
        avg_similarity = sum(p["similarity_score"] for p in similar) / len(similar)
        confidence = agreement * avg_similarity

        return {
            "predicted_return": predicted_return,
            "direction": direction,
            "confidence": confidence,
            "num_patterns": len(similar),
            "similar_patterns": similar[:5],
        }

    def run_analysis(self, symbol: str) -> dict:
        """
        Run similarity analysis for current state.
        Uses aggregated embedding from Qdrant for the symbol.

        Args:
            symbol: Symbol to analyze

        Returns:
            Analysis results with predictions
        """
        if self.qdrant is None:
            self.connect()

        # Get aggregated embedding from the embedding job
        aggregated = self.embedding_job.get_aggregated_embedding(symbol)
        if aggregated is None:
            return {"error": f"No patterns found for {symbol}"}

        prediction = self.predict_from_similar(symbol, aggregated)

        return {
            "symbol": symbol,
            "timestamp": datetime.now(tz=UTC).isoformat(),
            "prediction": prediction,
        }

    def close(self) -> None:
        """Close connections."""
        if self.qdrant:
            self.qdrant.close()
            self.qdrant = None
