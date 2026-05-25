"""
Multi-scale drift detection service.
Checks drift at configurable time scales using PSI and KS tests.

Usage:
  uv run main.py                          # Continuous mode (all scales, loop)
  uv run main.py --scale minute --once    # One-shot: check minute scale (CronJob)
  uv run main.py --scale hourly --once    # One-shot: check hourly scale (CronJob)
  uv run main.py --scale daily --once     # One-shot: check daily scale (CronJob)
  uv run main.py --scale weekly --once    # One-shot: check weekly scale (CronJob)
"""

import argparse
import logging
import os
import time
from datetime import UTC, datetime, timedelta
from typing import Any

import clickhouse_connect
import numpy as np
import redis
import yaml
from prometheus_client import Counter, Gauge, start_http_server

from ks_test import ks_test
from psi import calculate_psi

# Pyroscope continuous profiling — opt-in via PYROSCOPE_SERVER_ADDRESS
# (set by platform pipeline-config ConfigMap). Unset (tests / local dev)
# = profiler disabled, service runs unchanged.
if os.environ.get("PYROSCOPE_SERVER_ADDRESS"):
    import pyroscope

    pyroscope.configure(
        application_name=f"{os.environ.get('USE_CASE', 'platform')}.drift",
        server_address=os.environ["PYROSCOPE_SERVER_ADDRESS"],
        tags={
            "use_case": os.environ.get("USE_CASE", "platform"),
            "service": "drift",
        },
    )

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Metrics
DRIFT_DETECTED = Counter(
    "drift_detected_total", "Drift detections", ["scale", "feature"]
)
DRIFT_PSI = Gauge("drift_psi", "PSI value", ["scale", "feature"])
DRIFT_KS = Gauge("drift_ks_pvalue", "KS p-value", ["scale", "feature"])


class Config:
    """Configuration from environment"""

    CLICKHOUSE_HOST = os.getenv("CLICKHOUSE_HOST", "localhost")
    CLICKHOUSE_PORT = int(os.getenv("CLICKHOUSE_PORT", "8123"))
    CLICKHOUSE_DB = os.getenv("CLICKHOUSE_DB", "features")
    CLICKHOUSE_USER = os.getenv("CLICKHOUSE_USER", "default")
    CLICKHOUSE_PASSWORD = os.getenv("CLICKHOUSE_PASSWORD", "")
    CLICKHOUSE_TABLE = os.getenv(
        "CLICKHOUSE_TABLE", "data_features"
    )
    # Sink table receiving per-scale drift metrics. Argo CronWorkflow
    # `retrain-on-drift` polls this table — keep the name aligned with
    # the use-case `init_clickhouse.sql` gold layer DDL.
    DRIFT_SINK_TABLE = os.getenv("DRIFT_SINK_TABLE", "gold.drift_multi_scale")
    # Symbol dimension is multi-asset/aggregate by design — drift detector
    # iterates feature columns not symbols. ALL means "aggregate across all
    # symbols observed in the comparison window".
    DRIFT_SINK_SYMBOL = os.getenv("DRIFT_SINK_SYMBOL", "ALL")
    VALKEY_HOST = os.getenv("VALKEY_HOST", "localhost")
    VALKEY_PORT = int(os.getenv("VALKEY_PORT", "6379"))
    VALKEY_PASSWORD = os.getenv("VALKEY_PASSWORD", "")
    METRICS_PORT = int(os.getenv("METRICS_PORT", "8083"))
    CONFIG_PATH = os.getenv("CONFIG_PATH", "/app/config.yaml")


DEFAULT_SCALES = {
    "minute": {
        "reference_window": "6h",
        "comparison_window": "5m",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.01,
        "trigger_retrain": False,
    },
    "hourly": {
        "reference_window": "24h",
        "comparison_window": "1h",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.03,
        "trigger_retrain": True,
    },
    "hour": {
        "reference_window": "24h",
        "comparison_window": "1h",
        "psi_warning": 0.10,
        "psi_severe": 0.20,
        "ks_pvalue": 0.03,
        "trigger_retrain": True,
    },
    "daily": {
        "reference_window": "30d",
        "comparison_window": "24h",
        "psi_warning": 0.20,
        "psi_severe": 0.30,
        "ks_pvalue": 0.05,
        "trigger_retrain": True,
    },
    "weekly": {
        "reference_window": "90d",
        "comparison_window": "7d",
        "psi_warning": 0.20,
        "psi_severe": 0.30,
        "ks_pvalue": 0.05,
        "trigger_retrain": True,
    },
}


def load_config() -> dict:
    """Load drift config from yaml or env vars"""
    try:
        with open(Config.CONFIG_PATH) as f:
            cfg = yaml.safe_load(f)
    except Exception:
        cfg = {"scales": DEFAULT_SCALES}

    # Override features from env
    env_features = os.getenv("DRIFT_FEATURES_TO_MONITOR", "")
    if env_features:
        cfg["features_to_monitor"] = [
            f.strip() for f in env_features.split(",") if f.strip()
        ]

    if not cfg.get("scales"):
        cfg["scales"] = DEFAULT_SCALES

    return cfg


def get_clickhouse_client() -> Any:
    return clickhouse_connect.get_client(
        host=Config.CLICKHOUSE_HOST,
        port=Config.CLICKHOUSE_PORT,
        database=Config.CLICKHOUSE_DB,
        username=Config.CLICKHOUSE_USER,
        password=Config.CLICKHOUSE_PASSWORD,
    )


def insert_drift_metrics(
    client: Any,
    scale_name: str,
    feature: str,
    psi: float,
    ks_stat: float,
    ks_pvalue: float,
    drift_detected: int,
    severity: str,
    trigger_retrain: int,
) -> None:
    """Persist per-scale drift result to gold.drift_multi_scale.

    Argo CronWorkflow `retrain-on-drift` polls this sink to decide whether
    to fire the KFP retraining_pipeline run. The Valkey pubsub publish
    that follows is observability-only (volatile, no durable consumer).
    """
    now = datetime.now(tz=UTC)
    table = Config.DRIFT_SINK_TABLE
    if "." in table:
        db, name = table.split(".", 1)
    else:
        db, name = Config.CLICKHOUSE_DB, table
    client.insert(
        table=name,
        database=db,
        data=[[
            Config.DRIFT_SINK_SYMBOL,
            now,
            scale_name,
            feature,
            float(psi),
            float(ks_stat),
            float(ks_pvalue),
            int(drift_detected),
            severity,
            int(trigger_retrain),
        ]],
        column_names=[
            "symbol",
            "timestamp",
            "scale",
            "feature_name",
            "psi_value",
            "ks_statistic",
            "ks_pvalue",
            "drift_detected",
            "severity",
            "trigger_retrain",
        ],
    )


def get_valkey_client() -> Any:
    return redis.Redis(
        host=Config.VALKEY_HOST,
        port=Config.VALKEY_PORT,
        password=Config.VALKEY_PASSWORD or None,
    )


def query_feature_data(
    client: Any, feature: str, start: datetime, end: datetime
) -> np.ndarray:
    """Query feature data from ClickHouse"""
    table = Config.CLICKHOUSE_TABLE
    query = f"""
    SELECT {feature}
    FROM {table}
    WHERE timestamp >= '{start.strftime("%Y-%m-%d %H:%M:%S")}'
      AND timestamp < '{end.strftime("%Y-%m-%d %H:%M:%S")}'
      AND {feature} IS NOT NULL
    """
    result = client.query(query)
    return np.array([row[0] for row in result.result_rows])


def check_scale(
    ch_client: Any,
    valkey_client: Any,
    scale_name: str,
    scale_config: dict,
    features: list[str],
) -> int:
    """Run drift check for a single scale. Returns number of drifts detected."""
    now = datetime.now(tz=UTC)
    ref_window = parse_duration(scale_config["reference_window"])
    comp_window = parse_duration(scale_config["comparison_window"])

    ref_start = now - ref_window
    comp_start = now - comp_window
    drift_count = 0

    for feature in features:
        try:
            ref_data = query_feature_data(ch_client, feature, ref_start, comp_start)
            comp_data = query_feature_data(ch_client, feature, comp_start, now)

            if len(ref_data) < 10 or len(comp_data) < 5:
                logger.info(
                    f"  {scale_name}/{feature}: insufficient data "
                    f"(ref={len(ref_data)}, comp={len(comp_data)})"
                )
                continue

            psi = calculate_psi(ref_data, comp_data)
            ks_stat, ks_pvalue = ks_test(ref_data, comp_data)

            DRIFT_PSI.labels(scale=scale_name, feature=feature).set(psi)
            DRIFT_KS.labels(scale=scale_name, feature=feature).set(ks_pvalue)

            psi_exceeded = psi > scale_config["psi_severe"]
            ks_failed = ks_pvalue < scale_config["ks_pvalue"]
            drift_flag = 1 if (psi_exceeded or ks_failed) else 0
            severity = (
                "SEVERE" if psi > scale_config.get("psi_severe", 0.3)
                else ("WARNING" if drift_flag else "OK")
            )
            trigger_retrain = (
                1 if drift_flag and scale_config.get("trigger_retrain", False) else 0
            )

            # Persist EVERY result (drift or not) so the retrain workflow's
            # 6h window query has signal even during calm periods — and so
            # `severity='OK'` rows are visible for SLO denominators.
            try:
                insert_drift_metrics(
                    ch_client,
                    scale_name,
                    feature,
                    psi,
                    ks_stat,
                    ks_pvalue,
                    drift_flag,
                    severity,
                    trigger_retrain,
                )
            except Exception as ins_err:
                logger.error(
                    f"  {scale_name}/{feature}: sink insert failed - {ins_err}"
                )

            if drift_flag:
                drift_count += 1
                DRIFT_DETECTED.labels(scale=scale_name, feature=feature).inc()
                logger.warning(
                    f"  DRIFT {severity}: {scale_name}/{feature} "
                    f"PSI={psi:.4f} KS_p={ks_pvalue:.4f}"
                )

                if scale_config.get("trigger_retrain", False):
                    valkey_client.publish(
                        "drift-events", f"{scale_name}:{feature}:{psi:.4f}"
                    )
            else:
                logger.info(
                    f"  {scale_name}/{feature}: OK "
                    f"PSI={psi:.4f} KS_p={ks_pvalue:.4f}"
                )

        except Exception as e:
            logger.error(f"  {scale_name}/{feature}: error - {e}")

    return drift_count


def parse_duration(s: str) -> timedelta:
    """Parse duration string like '1m', '1h', '1d'"""
    value = int(s[:-1])
    unit = s[-1]
    if unit == "m":
        return timedelta(minutes=value)
    if unit == "h":
        return timedelta(hours=value)
    if unit == "d":
        return timedelta(days=value)
    return timedelta(hours=1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Multi-scale drift detector")
    parser.add_argument(
        "--scale",
        type=str,
        default=None,
        help="Run specific scale only (minute, hourly, hour, daily, weekly)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run once and exit (for CronJob mode)",
    )
    args = parser.parse_args()

    config = load_config()
    features = config.get("features_to_monitor", [])

    if not features:
        logger.error("No features to monitor. Set DRIFT_FEATURES_TO_MONITOR env var.")
        return

    ch_client = get_clickhouse_client()
    valkey_client = get_valkey_client()

    scales_to_check = config.get("scales", {})
    if args.scale:
        if args.scale in scales_to_check:
            scales_to_check = {args.scale: scales_to_check[args.scale]}
        else:
            logger.error(f"Unknown scale: {args.scale}. Available: {list(scales_to_check.keys())}")
            return

    if args.once:
        # One-shot mode (CronJob)
        for scale_name, scale_config in scales_to_check.items():
            logger.info(f"Drift check: {scale_name} scale")
            drift_count = check_scale(
                ch_client, valkey_client, scale_name, scale_config, features
            )
            logger.info(f"  Result: {drift_count} drifts detected")
    else:
        # Continuous mode (Deployment)
        start_http_server(Config.METRICS_PORT)
        logger.info(f"Drift detector started, metrics on port {Config.METRICS_PORT}")

        last_checks: dict[str, datetime] = {}
        while True:
            now = datetime.now(tz=UTC)
            for scale_name, scale_config in scales_to_check.items():
                last = last_checks.get(scale_name, datetime.min.replace(tzinfo=UTC))
                interval = parse_duration(scale_config.get("check_interval", "15m"))

                if now - last >= interval:
                    logger.info(f"Drift check: {scale_name} scale")
                    check_scale(
                        ch_client, valkey_client, scale_name, scale_config, features
                    )
                    last_checks[scale_name] = now

            time.sleep(10)


if __name__ == "__main__":
    main()
