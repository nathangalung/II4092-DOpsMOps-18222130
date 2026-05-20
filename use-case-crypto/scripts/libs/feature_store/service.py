#!/usr/bin/env -S uv run python
"""Feature Store gRPC Service"""

import logging
import os
from concurrent import futures
from datetime import datetime, timezone
from typing import Dict, List

import grpc

from store import FeatureStore, FeatureStoreConfig

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FeatureStoreServicer:
    """gRPC service for feature store operations"""

    def __init__(self):
        self.store = FeatureStore(FeatureStoreConfig())

    def SetFeatures(self, request, context) -> Dict:
        """Set features in online store"""
        try:
            features = {f.name: f.value for f in request.features}

            self.store.online.set_features(
                request.entity_type,
                request.entity_id,
                features,
                request.ttl if request.HasField("ttl") else None,
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
                "feature_count": len(features),
            }
        except Exception as e:
            logger.error(f"SetFeatures failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def GetFeatures(self, request, context) -> Dict:
        """Get features from online store"""
        try:
            feature_names = (
                list(request.feature_names) if request.feature_names else None
            )

            features = self.store.online.get_features(
                request.entity_type, request.entity_id, feature_names
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
                "features": features,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        except Exception as e:
            logger.error(f"GetFeatures failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def GetBatchFeatures(self, request, context) -> Dict:
        """Get features for multiple entities"""
        try:
            feature_names = (
                list(request.feature_names) if request.feature_names else None
            )
            entity_ids = list(request.entity_ids)

            results = self.store.online.get_batch_features(
                request.entity_type, entity_ids, feature_names
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "results": results,
                "count": len(results),
            }
        except Exception as e:
            logger.error(f"GetBatchFeatures failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def MaterializeFeatures(self, request, context) -> Dict:
        """Write features to both stores"""
        try:
            features = {f.name: f.value for f in request.features}

            timestamp = None
            if request.HasField("timestamp"):
                timestamp = datetime.fromisoformat(request.timestamp)

            self.store.materialize_features(
                request.entity_type, request.entity_id, features, timestamp
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
                "online": True,
                "offline": True,
            }
        except Exception as e:
            logger.error(f"MaterializeFeatures failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def AppendSequence(self, request, context) -> Dict:
        """Append to feature sequence"""
        try:
            features = {f.name: f.value for f in request.features}

            self.store.online.append_sequence(
                request.entity_type,
                request.entity_id,
                features,
                request.max_length or 1000,
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
            }
        except Exception as e:
            logger.error(f"AppendSequence failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def GetSequence(self, request, context) -> Dict:
        """Get feature sequence"""
        try:
            sequence = self.store.online.get_sequence(
                request.entity_type, request.entity_id, request.length or 60
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
                "sequence": sequence,
                "length": len(sequence),
            }
        except Exception as e:
            logger.error(f"GetSequence failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def GetHistoricalFeatures(self, request, context) -> Dict:
        """Get historical features from offline store"""
        try:
            start_time = datetime.fromisoformat(request.start_time)
            end_time = datetime.fromisoformat(request.end_time)
            feature_names = (
                list(request.feature_names) if request.feature_names else None
            )

            data = self.store.offline.get_historical_features(
                request.entity_type,
                request.entity_id,
                start_time,
                end_time,
                feature_names,
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
                "data": data,
                "count": len(data),
            }
        except Exception as e:
            logger.error(f"GetHistoricalFeatures failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def GetTrainingData(self, request, context) -> Dict:
        """Get training data from offline store"""
        try:
            start_time = datetime.fromisoformat(request.start_time)
            end_time = datetime.fromisoformat(request.end_time)
            entity_ids = list(request.entity_ids)
            feature_names = list(request.feature_names)

            data = self.store.offline.get_training_data(
                request.entity_type, entity_ids, start_time, end_time, feature_names
            )

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "data": data,
                "count": len(data),
            }
        except Exception as e:
            logger.error(f"GetTrainingData failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}

    def SyncToOnline(self, request, context) -> Dict:
        """Sync offline features to online store"""
        try:
            self.store.sync_to_online(request.entity_type, request.entity_id)

            return {
                "status": "SUCCESS",
                "entity_type": request.entity_type,
                "entity_id": request.entity_id,
            }
        except Exception as e:
            logger.error(f"SyncToOnline failed: {e}")
            context.set_code(grpc.StatusCode.INTERNAL)
            return {"status": "ERROR", "message": str(e)}


def serve():
    """Start feature store gRPC server"""
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))

    servicer = FeatureStoreServicer()

    server.add_insecure_port("[::]:50054")
    server.start()
    logger.info("Feature store server started on port 50054")
    server.wait_for_termination()


if __name__ == "__main__":
    serve()
