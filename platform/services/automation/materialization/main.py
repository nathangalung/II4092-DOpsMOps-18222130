"""
Feast feature materialization job.
Applies feature definitions then materializes from offline (ClickHouse) to
online (Valkey — Redis-RESP-compatible online store).
"""

import logging
import os
import subprocess
from datetime import UTC, datetime, timedelta

from feast import FeatureStore

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def main() -> None:
    """Apply feature definitions and run materialization."""
    repo_path = os.getenv("FEAST_REPO_PATH", "/app/feature_repo")

    # Step 1: Apply feature definitions to registry
    logger.info(f"Applying feature definitions from {repo_path}")
    result = subprocess.run(
        ["feast", "apply"],
        cwd=repo_path,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        logger.error(f"feast apply failed: {result.stderr}")
    else:
        logger.info(f"feast apply: {result.stdout.strip()}")

    # Step 2: Materialize features (offline → online)
    store = FeatureStore(repo_path=repo_path)

    end_date = datetime.now(tz=UTC)
    hours = int(os.getenv("MATERIALIZE_HOURS", "24"))
    start_date = end_date - timedelta(hours=hours)

    logger.info(f"Materializing features from {start_date} to {end_date}")
    store.materialize(start_date=start_date, end_date=end_date)
    logger.info("Materialization complete")


if __name__ == "__main__":
    main()
