"""
Evidently drift report generator.
Reads reference and current data from ClickHouse feature layer,
generates DataDrift and DataSummary reports using Evidently 0.7+ API,
and saves them to the Evidently workspace via REST API or as local HTML.

Usage:
  uv run main.py                  # Generate reports for all features
  uv run main.py --report drift   # Only drift report
  uv run main.py --report summary # Only data summary report
"""

import logging
import os
from datetime import UTC, datetime, timedelta

import clickhouse_connect
import pandas as pd
import requests
from evidently import Report
from evidently.presets import DataDriftPreset, DataSummaryPreset

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class Config:
    """Configuration from environment variables."""

    CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "localhost")
    CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
    FEATURES_TABLE = os.getenv(
        "EVIDENTLY_FEATURES_TABLE", "gold.fct_features"
    )
    EVIDENTLY_HOST = os.getenv("EVIDENTLY_HOST", "localhost")
    EVIDENTLY_PORT = int(os.getenv("EVIDENTLY_PORT", "8000"))
    REFERENCE_WINDOW_HOURS = int(os.getenv("REFERENCE_WINDOW_HOURS", "72"))
    CURRENT_WINDOW_HOURS = int(os.getenv("CURRENT_WINDOW_HOURS", "24"))
    VALID_SYMBOLS = os.getenv("VALID_SYMBOLS", "")
    TARGET_COLUMN = os.getenv("TARGET_COLUMN", "value")
    PROJECT_NAME = os.getenv("EVIDENTLY_PROJECT", "pipeline-monitoring")
    EXCLUDE_COLUMNS = os.getenv(
        "EXCLUDE_COLUMNS",
        "symbol,timestamp,date,hour,data_type,created_at,computed_at",
    )


def get_clickhouse_client():
    return clickhouse_connect.get_client(
        host=Config.CLICKHOUSE_HOST,
        port=Config.CLICKHOUSE_PORT,
    )


def load_data(
    client, symbol: str, start: datetime, end: datetime
) -> pd.DataFrame:
    """Load feature data from ClickHouse for a symbol within time window."""
    query = f"""
    SELECT *
    FROM {Config.FEATURES_TABLE}
    WHERE symbol = '{symbol}'
      AND timestamp >= '{start.strftime("%Y-%m-%d %H:%M:%S")}'
      AND timestamp < '{end.strftime("%Y-%m-%d %H:%M:%S")}'
    ORDER BY timestamp
    """
    df = client.query_df(query)
    logger.info(
        f"Loaded {len(df)} rows for {symbol} "
        f"({start.strftime('%Y-%m-%d %H:%M')} to {end.strftime('%Y-%m-%d %H:%M')})"
    )
    return df


def get_feature_columns(df: pd.DataFrame) -> list[str]:
    """Get numeric feature columns, excluding metadata."""
    exclude = {
        c.strip() for c in Config.EXCLUDE_COLUMNS.split(",") if c.strip()
    }
    return [
        c for c in df.columns
        if c not in exclude and df[c].dtype in ("float64", "float32", "int64", "int32")
    ]


def generate_drift_report(
    reference: pd.DataFrame,
    current: pd.DataFrame,
    feature_cols: list[str],
):
    """Generate data drift report using PSI method. Returns Snapshot."""
    report = Report([DataDriftPreset()])
    snapshot = report.run(
        reference_data=reference[feature_cols],
        current_data=current[feature_cols],
    )
    return snapshot


def generate_summary_report(
    reference: pd.DataFrame,
    current: pd.DataFrame,
    feature_cols: list[str],
):
    """Generate data summary report. Returns Snapshot."""
    report = Report([DataSummaryPreset()])
    snapshot = report.run(
        reference_data=reference[feature_cols],
        current_data=current[feature_cols],
    )
    return snapshot


def ensure_project(base_url: str) -> str | None:
    """Ensure Evidently project exists, return project ID."""
    try:
        resp = requests.get(f"{base_url}/api/projects", timeout=10)
        resp.raise_for_status()
        projects = resp.json()

        for project in projects:
            if project.get("name") == Config.PROJECT_NAME:
                return project["id"]

        # Create project
        resp = requests.post(
            f"{base_url}/api/projects",
            json={"name": Config.PROJECT_NAME},
            timeout=10,
        )
        resp.raise_for_status()
        project_id = resp.json()["id"]
        logger.info(f"Created Evidently project: {Config.PROJECT_NAME}")
        return project_id
    except Exception as e:
        logger.warning(f"Could not connect to Evidently API: {e}")
        return None


def save_snapshot(
    base_url: str, project_id: str, snapshot, report_type: str
) -> bool:
    """Save report snapshot to Evidently workspace via API."""
    try:
        report_json = snapshot.json()
        resp = requests.post(
            f"{base_url}/api/projects/{project_id}/snapshots",
            data=report_json,
            headers={"Content-Type": "application/json"},
            timeout=30,
        )
        resp.raise_for_status()
        logger.info(f"Saved {report_type} snapshot to Evidently workspace")
        return True
    except Exception as e:
        logger.warning(f"Could not save snapshot to Evidently: {e}")
        return False


def process_symbol(
    ch_client,
    symbol: str,
    report_types: list[str],
    base_url: str,
    project_id: str | None,
) -> int:
    """Generate reports for a single symbol. Returns count of reports generated."""
    now = datetime.now(tz=UTC)
    ref_start = now - timedelta(hours=Config.REFERENCE_WINDOW_HOURS)
    ref_end = now - timedelta(hours=Config.CURRENT_WINDOW_HOURS)
    curr_start = ref_end
    curr_end = now

    reference = load_data(ch_client, symbol, ref_start, ref_end)
    current = load_data(ch_client, symbol, curr_start, curr_end)

    if len(reference) < 10:
        logger.warning(
            f"Insufficient reference data for {symbol} ({len(reference)} rows)"
        )
        return 0
    if len(current) < 5:
        logger.warning(
            f"Insufficient current data for {symbol} ({len(current)} rows)"
        )
        return 0

    feature_cols = get_feature_columns(reference)
    if not feature_cols:
        logger.warning(f"No numeric feature columns for {symbol}")
        return 0

    logger.info(
        f"Generating reports for {symbol}: "
        f"ref={len(reference)} rows, curr={len(current)} rows, "
        f"features={len(feature_cols)}"
    )

    count = 0
    if "drift" in report_types:
        snapshot = generate_drift_report(reference, current, feature_cols)
        if project_id:
            save_snapshot(base_url, project_id, snapshot, f"drift_{symbol}")
        else:
            path = f"/tmp/evidently_drift_{symbol}_{now.strftime('%Y%m%d')}.html"
            snapshot.save_html(path)
            logger.info(f"Saved drift report to {path}")
        count += 1

    if "summary" in report_types:
        snapshot = generate_summary_report(reference, current, feature_cols)
        if project_id:
            save_snapshot(base_url, project_id, snapshot, f"summary_{symbol}")
        else:
            path = f"/tmp/evidently_summary_{symbol}_{now.strftime('%Y%m%d')}.html"
            snapshot.save_html(path)
            logger.info(f"Saved summary report to {path}")
        count += 1

    return count


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Evidently Report Generator")
    parser.add_argument(
        "--report",
        type=str,
        default="all",
        choices=["drift", "summary", "all"],
        help="Report type to generate",
    )
    args = parser.parse_args()

    report_types = ["drift", "summary"] if args.report == "all" else [args.report]

    # Determine symbols
    if Config.VALID_SYMBOLS:
        symbols = [s.strip() for s in Config.VALID_SYMBOLS.split(",") if s.strip()]
    else:
        logger.error("No symbols configured. Set VALID_SYMBOLS.")
        return

    # Connect to Evidently
    base_url = f"http://{Config.EVIDENTLY_HOST}:{Config.EVIDENTLY_PORT}"
    project_id = ensure_project(base_url)
    if not project_id:
        logger.warning("Running without Evidently API — saving reports locally")

    # Generate reports
    ch_client = get_clickhouse_client()
    total_reports = 0
    for symbol in symbols:
        try:
            count = process_symbol(
                ch_client, symbol, report_types, base_url, project_id
            )
            total_reports += count
        except Exception as e:
            logger.error(f"Report generation failed for {symbol}: {e}")

    logger.info(f"Report generation complete: {total_reports} reports")


if __name__ == "__main__":
    main()
