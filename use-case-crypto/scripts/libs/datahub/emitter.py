#!/usr/bin/env -S uv run python
"""DataHub Metadata Emitter"""

import logging
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


DATAHUB_GMS_URL = os.getenv(
    "DATAHUB_GMS_URL", "http://datahub-gms.data-governance.svc.cluster.local:8080"
)


class DatasetMetadata:
    """Dataset metadata structure"""

    def __init__(self, name: str, platform: str):
        self.name = name
        self.platform = platform
        self.description = ""
        self.schema_fields = []
        self.tags = []
        self.owners = []
        self.custom_properties = {}


class MetadataEmitter:
    """Emit metadata to DataHub"""

    def __init__(self, gms_url: str = None):
        self.gms_url = gms_url or DATAHUB_GMS_URL
        self._client = None

    def _get_client(self):
        """Lazy client initialization"""
        if self._client is None:
            try:
                from datahub.emitter.rest_emitter import DatahubRestEmitter

                self._client = DatahubRestEmitter(self.gms_url)
            except ImportError:
                logger.warning("datahub package not installed")
                return None
        return self._client

    def emit_dataset(self, metadata: DatasetMetadata) -> bool:
        """Emit dataset metadata"""
        client = self._get_client()
        if not client:
            logger.info(f"Would emit dataset: {metadata.name}")
            return False

        try:
            from datahub.metadata.schema_classes import (
                DatasetPropertiesClass,
                SchemaMetadataClass,
                SchemaFieldClass,
                StringTypeClass,
                NumberTypeClass,
            )
            from datahub.emitter.mce_builder import make_dataset_urn

            dataset_urn = make_dataset_urn(
                platform=metadata.platform, name=metadata.name
            )

            properties = DatasetPropertiesClass(
                name=metadata.name,
                description=metadata.description,
                customProperties=metadata.custom_properties,
            )

            client.emit_mcp(
                entity_urn=dataset_urn,
                aspect_name="datasetProperties",
                aspect=properties,
            )

            logger.info(f"Emitted dataset: {metadata.name}")
            return True

        except Exception as e:
            logger.error(f"Failed to emit dataset: {e}")
            return False

    def emit_model(
        self,
        model_name: str,
        model_version: str,
        metrics: Dict[str, float],
        hyperparameters: Dict[str, any],
    ) -> bool:
        """Emit ML model metadata"""
        client = self._get_client()
        if not client:
            logger.info(f"Would emit model: {model_name}:{model_version}")
            return False

        try:
            from datahub.metadata.schema_classes import MLModelPropertiesClass
            from datahub.emitter.mce_builder import make_ml_model_urn

            model_urn = make_ml_model_urn(
                platform="mlflow", name=model_name, env="PROD"
            )

            properties = MLModelPropertiesClass(
                customProperties={
                    "version": model_version,
                    **{f"metric_{k}": str(v) for k, v in metrics.items()},
                    **{f"param_{k}": str(v) for k, v in hyperparameters.items()},
                }
            )

            client.emit_mcp(
                entity_urn=model_urn, aspect_name="mlModelProperties", aspect=properties
            )

            logger.info(f"Emitted model: {model_name}:{model_version}")
            return True

        except Exception as e:
            logger.error(f"Failed to emit model: {e}")
            return False

    def emit_pipeline(
        self, pipeline_name: str, input_datasets: List[str], output_datasets: List[str]
    ) -> bool:
        """Emit data pipeline metadata"""
        client = self._get_client()
        if not client:
            logger.info(f"Would emit pipeline: {pipeline_name}")
            return False

        try:
            from datahub.metadata.schema_classes import (
                DataJobInputOutputClass,
                DataJobInfoClass,
            )
            from datahub.emitter.mce_builder import make_data_job_urn, make_dataset_urn

            job_urn = make_data_job_urn(
                orchestrator="airflow",
                flow_id=pipeline_name,
                job_id=f"{pipeline_name}_job",
            )

            input_urns = [make_dataset_urn("kafka", ds) for ds in input_datasets]
            output_urns = [make_dataset_urn("clickhouse", ds) for ds in output_datasets]

            io = DataJobInputOutputClass(
                inputDatasets=input_urns, outputDatasets=output_urns
            )

            client.emit_mcp(
                entity_urn=job_urn, aspect_name="dataJobInputOutput", aspect=io
            )

            logger.info(f"Emitted pipeline: {pipeline_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to emit pipeline: {e}")
            return False

    def emit_feature(
        self, feature_name: str, entity_type: str, description: str, data_type: str
    ) -> bool:
        """Emit feature metadata"""
        client = self._get_client()
        if not client:
            logger.info(f"Would emit feature: {feature_name}")
            return False

        try:
            from datahub.metadata.schema_classes import MLFeaturePropertiesClass
            from datahub.emitter.mce_builder import make_ml_feature_urn

            feature_urn = make_ml_feature_urn(
                feature_table_name=f"{entity_type}_features", feature_name=feature_name
            )

            properties = MLFeaturePropertiesClass(
                description=description, dataType=data_type
            )

            client.emit_mcp(
                entity_urn=feature_urn,
                aspect_name="mlFeatureProperties",
                aspect=properties,
            )

            logger.info(f"Emitted feature: {feature_name}")
            return True

        except Exception as e:
            logger.error(f"Failed to emit feature: {e}")
            return False


def emit_all_features():
    """Emit all feature definitions"""
    from ingestion_config import CRYPTO_FEATURE_DEFINITIONS, STOCK_FEATURE_DEFINITIONS

    emitter = MetadataEmitter()

    for feature in CRYPTO_FEATURE_DEFINITIONS:
        emitter.emit_feature(
            feature["name"], "crypto", feature["description"], feature["type"]
        )

    for feature in STOCK_FEATURE_DEFINITIONS:
        emitter.emit_feature(
            feature["name"], "stock", feature["description"], feature["type"]
        )


def emit_pipeline_lineage():
    """Emit pipeline lineage"""
    emitter = MetadataEmitter()

    emitter.emit_pipeline("crypto_etl", ["crypto.raw_data"], ["crypto_features"])

    emitter.emit_pipeline("stock_etl", ["stock.raw_data"], ["stock_features"])

    emitter.emit_pipeline(
        "crypto_training", ["crypto_features"], ["crypto_predictions"]
    )

    emitter.emit_pipeline("stock_training", ["stock_features"], ["stock_predictions"])


if __name__ == "__main__":
    emit_all_features()
    emit_pipeline_lineage()
