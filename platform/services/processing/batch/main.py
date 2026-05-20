"""
Batch processing service entry point.
Runs feature engineering jobs on historical data from ClickHouse.
"""

import argparse
import logging
import sys
from datetime import datetime

from config import Config, load_config
from jobs import BackfillJob, FeatureEngineeringJob, SentimentAggregationJob

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def run_features(config: Config) -> None:
    """Run feature engineering job for recent data."""
    logger.info("Starting feature engineering job")
    job = FeatureEngineeringJob(config)
    job.connect()
    job.run()
    job.close()
    logger.info("Feature engineering job completed")


def run_backfill(
    config: Config, start_date: str | None, end_date: str | None, chunk_days: int
) -> None:
    """Run backfill job for historical data."""
    logger.info("Starting backfill job")

    start_time = datetime.fromisoformat(start_date) if start_date else None
    end_time = datetime.fromisoformat(end_date) if end_date else None

    job = BackfillJob(config)
    job.run(start_time=start_time, end_time=end_time, chunk_days=chunk_days)
    logger.info("Backfill job completed")


def run_incremental(config: Config, hours: int) -> None:
    """Run incremental backfill for recent hours."""
    logger.info(f"Starting incremental backfill for last {hours} hours")
    job = BackfillJob(config)
    job.run_incremental(hours=hours)
    logger.info("Incremental backfill completed")


def run_sentiment() -> None:
    """Run sentiment aggregation job."""
    logger.info("Starting sentiment aggregation job")
    job = SentimentAggregationJob()
    job.connect()
    job.run()
    job.close()
    logger.info("Sentiment aggregation job completed")


def main() -> None:
    parser = argparse.ArgumentParser(description="Batch processing service")
    parser.add_argument(
        "--mode",
        choices=["features", "backfill", "incremental", "sentiment"],
        default="features",
        help="Job mode: features (default), backfill, incremental, or sentiment",
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to config.yaml file",
    )
    parser.add_argument(
        "--start-date",
        type=str,
        default=None,
        help="Start date for backfill (ISO format)",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=None,
        help="End date for backfill (ISO format)",
    )
    parser.add_argument(
        "--chunk-days",
        type=int,
        default=7,
        help="Days per chunk for backfill (default: 7)",
    )
    parser.add_argument(
        "--hours",
        type=int,
        default=24,
        help="Hours to look back for incremental mode (default: 24)",
    )

    args = parser.parse_args()

    # Load configuration
    config = load_config(args.config)

    if not config.enabled:
        logger.info("Batch processing is disabled in configuration")
        sys.exit(0)

    # Run selected mode
    if args.mode == "features":
        run_features(config)
    elif args.mode == "backfill":
        if not config.backfill_enabled:
            logger.info("Backfill is disabled in configuration")
            sys.exit(0)
        run_backfill(config, args.start_date, args.end_date, args.chunk_days)
    elif args.mode == "incremental":
        run_incremental(config, args.hours)
    elif args.mode == "sentiment":
        run_sentiment()


if __name__ == "__main__":
    main()
