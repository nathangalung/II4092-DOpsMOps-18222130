"""
Backfill job for historical feature computation.
Processes historical data in chunks to compute features for training.
"""

import logging
from datetime import UTC, datetime, timedelta

from config import Config
from jobs.features import FeatureEngineeringJob

logger = logging.getLogger(__name__)


class BackfillJob:
    """
    Backfill job for computing historical features.

    This job processes historical data in chunks to avoid memory issues
    and to allow for incremental processing.
    """

    def __init__(self, config: Config) -> None:
        self.config = config
        self.feature_job = FeatureEngineeringJob(config)

    def run(
        self,
        start_time: datetime | None = None,
        end_time: datetime | None = None,
        chunk_days: int = 7,
    ) -> None:
        """
        Run backfill for historical data.

        Args:
            start_time: Start of backfill period (default: config.train_start)
            end_time: End of backfill period (default: config.validation_end)
            chunk_days: Number of days to process per chunk
        """
        # Use config dates if not specified
        if start_time is None:
            start_time = datetime.fromisoformat(self.config.train_start)
        if end_time is None:
            end_time = datetime.fromisoformat(self.config.validation_end)

        logger.info(f"Starting backfill from {start_time} to {end_time}")
        logger.info(f"Processing in {chunk_days}-day chunks")

        self.feature_job.connect()

        # Process in chunks
        current_start = start_time
        chunk_delta = timedelta(days=chunk_days)
        total_chunks = 0

        while current_start < end_time:
            current_end = min(current_start + chunk_delta, end_time)

            logger.info(f"Processing chunk: {current_start} to {current_end}")

            try:
                self.feature_job.run(start_time=current_start, end_time=current_end)
                total_chunks += 1
            except Exception as e:
                logger.error(f"Error processing chunk: {e}")

            current_start = current_end

        logger.info(f"Backfill complete. Processed {total_chunks} chunks.")
        self.feature_job.close()

    def run_incremental(self, hours: int = 24) -> None:
        """
        Run incremental backfill for recent data.

        Args:
            hours: Number of hours to look back
        """
        end_time = datetime.now(tz=UTC)
        start_time = end_time - timedelta(hours=hours)

        logger.info(f"Running incremental backfill for last {hours} hours")

        self.feature_job.connect()
        self.feature_job.run(start_time=start_time, end_time=end_time)
        self.feature_job.close()
