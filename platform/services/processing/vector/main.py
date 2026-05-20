"""
Vector processing service entry point.
Computes embeddings and performs similarity search for pattern matching.
"""

import argparse
import json
import logging
import os
import sys
from datetime import datetime
from typing import TYPE_CHECKING

from config import load_config
from jobs import EmbeddingJob, SimilaritySearchJob

if TYPE_CHECKING:
    from config import Config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

DEFAULT_SYMBOL = os.getenv("DEFAULT_SYMBOL", "SAMPLE-001")


def run_embeddings(
    config: "Config", start_date: str | None, end_date: str | None
) -> None:
    """Compute embeddings for time series windows."""
    logger.info("Starting embedding computation")

    start_time = datetime.fromisoformat(start_date) if start_date else None
    end_time = datetime.fromisoformat(end_date) if end_date else None

    job = EmbeddingJob(config)
    job.connect()
    job.run(start_time=start_time, end_time=end_time)
    job.close()
    logger.info("Embedding computation completed")


def run_analysis(config: "Config", symbol: str) -> None:
    """Run similarity analysis for a symbol."""
    logger.info(f"Running similarity analysis for {symbol}")

    job = SimilaritySearchJob(config)
    job.connect()
    result = job.run_analysis(symbol)
    job.close()

    print(json.dumps(result, indent=2, default=str))
    logger.info("Similarity analysis completed")


def main() -> None:
    parser = argparse.ArgumentParser(description="Vector processing service")
    parser.add_argument(
        "--mode",
        choices=["embeddings", "analysis"],
        default="embeddings",
        help="Job mode: embeddings (compute vectors) or analysis (similarity search)",
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
        help="Start date for embedding computation (ISO format)",
    )
    parser.add_argument(
        "--end-date",
        type=str,
        default=None,
        help="End date for embedding computation (ISO format)",
    )
    parser.add_argument(
        "--symbol",
        type=str,
        default=DEFAULT_SYMBOL,
        help="Symbol for analysis mode",
    )

    args = parser.parse_args()

    # Load configuration
    config = load_config(args.config)

    if not config.enabled:
        logger.info("Vector processing is disabled in configuration")
        sys.exit(0)

    # Run selected mode
    if args.mode == "embeddings":
        run_embeddings(config, args.start_date, args.end_date)
    elif args.mode == "analysis":
        run_analysis(config, args.symbol)


if __name__ == "__main__":
    main()
