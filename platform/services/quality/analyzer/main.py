"""Quality analyzer entry point."""

import logging
import os
import time
from pathlib import Path

import yaml

from jobs.expectations import ExpectationsRunner, SimplifiedExpectationsRunner
from jobs.outlier import OutlierDetector

HEALTH_FILE = Path("/tmp/healthy")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def load_config() -> dict:
    """Load configuration."""
    config_path = os.getenv("CONFIG_PATH", "/app/config.yaml")
    if os.path.exists(config_path):
        with open(config_path) as f:
            return yaml.safe_load(f)
    return {
        "quality": {
            "min_records": 100,
            "max_missing_percent": 5.0,
            "outlier_std": 3.0,
        }
    }


def run_analysis(config: dict, mode: str | None = None) -> None:
    """Run quality analysis."""
    quality_cfg = config.get("quality", {})

    if mode in (None, "outlier"):
        logger.info("Running outlier detection...")
        detector = OutlierDetector(std_threshold=quality_cfg.get("outlier_std", 3.0))
        detector.run()

    if mode in (None, "expectations"):
        logger.info("Running data expectations...")
        try:
            runner = ExpectationsRunner()
            runner.run()
        except Exception as e:
            logger.warning(f"Full GE runner failed ({e}), using simplified runner")
            runner = SimplifiedExpectationsRunner()
            runner.run()


def main() -> None:
    """Main entry point."""
    config = load_config()
    mode = os.getenv("ANALYSIS_MODE")
    HEALTH_FILE.touch()

    if os.getenv("CONTINUOUS", "false").lower() == "true":
        interval = int(os.getenv("INTERVAL_SECONDS", "300"))
        logger.info(f"Continuous mode, interval: {interval}s")

        while True:
            try:
                run_analysis(config, mode)
            except Exception as e:
                logger.error(f"Analysis failed: {e}")
            HEALTH_FILE.touch()
            time.sleep(interval)
    else:
        run_analysis(config, mode)
        HEALTH_FILE.touch()


if __name__ == "__main__":
    main()
