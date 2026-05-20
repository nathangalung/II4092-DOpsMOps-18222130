"""
Great Expectations runner for data quality validation.
Uses GE 1.x API for comprehensive data validation.

GENERIC: All column names, validation rules, and value ranges are
loaded from environment variables. Use-cases configure their own
expectations via ConfigMap.
"""

import json
import logging
import os
from datetime import UTC, datetime, timedelta
from typing import Any

import clickhouse_connect
import great_expectations as gx
import pandas as pd

logger = logging.getLogger(__name__)


def _parse_csv_env(key: str, default: str) -> list[str]:
    """Parse comma-separated environment variable into list."""
    return [v.strip() for v in os.getenv(key, default).split(",") if v.strip()]


def _parse_pair_rules(key: str, default: str) -> list[tuple[str, str]]:
    """Parse pair rules like 'A>B,C>D' into list of (column_A, column_B) tuples."""
    raw = os.getenv(key, default)
    if not raw:
        return []
    pairs = []
    for rule in raw.split(","):
        rule = rule.strip()
        if ">" in rule:
            a, b = rule.split(">", 1)
            pairs.append((a.strip(), b.strip()))
    return pairs


class ExpectationsRunner:
    """
    Runs Great Expectations validations on data using GE 1.x API.
    All expectations are config-driven via environment variables.
    """

    def __init__(self) -> None:
        """Initialize runner with GE context."""
        self.client = self._get_clickhouse_client()
        self.context = gx.get_context()

    def _get_clickhouse_client(self) -> Any:
        """Get ClickHouse client."""
        return clickhouse_connect.get_client(
            host=os.getenv("CLICKHOUSE_HOST", "clickhouse"),
            port=int(os.getenv("CLICKHOUSE_PORT", "8123")),
            database=os.getenv("CLICKHOUSE_DB", "features"),
            username=os.getenv("CLICKHOUSE_USER", "default"),
            password=os.getenv("CLICKHOUSE_PASSWORD", ""),
        )

    def _create_data_suite(self) -> gx.ExpectationSuite:
        """Create expectation suite from environment config."""
        suite_name = os.getenv("EXPECTATION_SUITE_NAME", "data_expectations")
        suite = gx.ExpectationSuite(name=suite_name)
        suite = self.context.suites.add(suite)

        # Required columns — from env (e.g., "symbol,timestamp,value")
        required_columns = _parse_csv_env("REQUIRED_COLUMNS", "symbol,timestamp")
        for col in required_columns:
            suite.add_expectation(gx.expectations.ExpectColumnToExist(column=col))
            suite.add_expectation(
                gx.expectations.ExpectColumnValuesToNotBeNull(column=col)
            )

        # Numeric range checks — from env (e.g., "price,value,score")
        range_columns = _parse_csv_env("RANGE_CHECK_COLUMNS", "")
        range_min = float(os.getenv("RANGE_CHECK_MIN", "0"))
        range_max = float(os.getenv("RANGE_CHECK_MAX", "1000000"))
        for col in range_columns:
            suite.add_expectation(
                gx.expectations.ExpectColumnValuesToBeBetween(
                    column=col,
                    min_value=range_min,
                    max_value=range_max,
                )
            )

        # Non-negative columns — from env (e.g., "volume,count")
        nonneg_columns = _parse_csv_env("NONNEG_COLUMNS", "")
        for col in nonneg_columns:
            suite.add_expectation(
                gx.expectations.ExpectColumnValuesToBeBetween(column=col, min_value=0)
            )

        # Pair comparison rules — from env (e.g., "col_a>col_b,col_c>col_d")
        pair_rules = _parse_pair_rules("PAIR_RULES", "")
        for col_a, col_b in pair_rules:
            suite.add_expectation(
                gx.expectations.ExpectColumnPairValuesAToBeGreaterThanB(
                    column_A=col_a,
                    column_B=col_b,
                    or_equal=True,
                )
            )

        # Valid entity set — from env (e.g., "ENTITY-A,ENTITY-B")
        valid_entities = _parse_csv_env("VALID_SYMBOLS", "")
        entity_column = os.getenv("ENTITY_COLUMN", "symbol")
        if valid_entities:
            suite.add_expectation(
                gx.expectations.ExpectColumnValuesToBeInSet(
                    column=entity_column,
                    value_set=valid_entities,
                )
            )

        return suite

    def _create_features_suite(self) -> gx.ExpectationSuite:
        """Create feature validation suite from environment config."""
        suite = gx.ExpectationSuite(name="features_expectations")
        suite = self.context.suites.add(suite)

        # Bounded features — from env (e.g., "feature_name:0:100,other_feature:0:1")
        bounded_features = os.getenv("BOUNDED_FEATURES", "")
        if bounded_features:
            for entry in bounded_features.split(","):
                entry = entry.strip()
                if not entry:
                    continue
                parts = entry.split(":")
                if len(parts) == 3:
                    col, min_v, max_v = parts
                    suite.add_expectation(
                        gx.expectations.ExpectColumnValuesToBeBetween(
                            column=col.strip(),
                            min_value=float(min_v),
                            max_value=float(max_v),
                        )
                    )

        # Feature pair rules — from env (e.g., "feature_a>feature_b")
        feature_pair_rules = _parse_pair_rules("FEATURE_PAIR_RULES", "")
        for col_a, col_b in feature_pair_rules:
            suite.add_expectation(
                gx.expectations.ExpectColumnPairValuesAToBeGreaterThanB(
                    column_A=col_a,
                    column_B=col_b,
                    or_equal=False,
                )
            )

        # Non-negative features — from env (e.g., "feature_x,feature_y")
        nonneg_features = _parse_csv_env("NONNEG_FEATURES", "")
        for col in nonneg_features:
            suite.add_expectation(
                gx.expectations.ExpectColumnValuesToBeBetween(column=col, min_value=0)
            )

        return suite

    def _validate_dataframe(
        self,
        df: pd.DataFrame,
        suite: gx.ExpectationSuite,
        name: str,
    ) -> Any:
        """Validate a DataFrame against a suite using GE 1.x API."""
        datasource = self.context.data_sources.add_pandas(f"pandas_{name}")
        data_asset = datasource.add_dataframe_asset(f"{name}_data")
        batch_definition = data_asset.add_batch_definition_whole_dataframe(
            f"{name}_batch"
        )

        validation_def = gx.ValidationDefinition(
            name=f"{name}_validation",
            data=batch_definition,
            suite=suite,
        )
        validation_def = self.context.validation_definitions.add(validation_def)

        checkpoint = gx.Checkpoint(
            name=f"{name}_checkpoint",
            validation_definitions=[validation_def],
        )
        checkpoint = self.context.checkpoints.add(checkpoint)

        return checkpoint.run(batch_parameters={"dataframe": df})

    def run(self) -> None:
        """Run all expectations."""
        try:
            self._validate_data()
            self._validate_features()
            logger.info("All GE expectations completed")
        except Exception as e:
            logger.error(f"GE expectations failed: {e}")
            raise

    def _validate_data(self) -> None:
        """Validate data from last hour."""
        end_time = datetime.now(tz=UTC).replace(tzinfo=None)
        start_time = end_time - timedelta(hours=1)

        data_table = os.getenv("DATA_TABLE", "raw_data")
        data_columns = os.getenv("DATA_COLUMNS", "symbol,timestamp")
        query = f"""
            SELECT {data_columns}
            FROM {data_table}
            WHERE timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
              AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
        """

        result = self.client.query(query)
        if not result.result_rows:
            logger.info("No data to validate")
            return

        col_names = [c.strip() for c in data_columns.split(",")]
        df = pd.DataFrame(result.result_rows, columns=col_names)

        data_type = os.getenv("DATA_TYPE", "raw")
        suite = self._create_data_suite()
        checkpoint_result = self._validate_dataframe(df, suite, data_type)
        self._store_validation_results(data_type, checkpoint_result, end_time)

    def _validate_features(self) -> None:
        """Validate features data from last hour."""
        end_time = datetime.now(tz=UTC).replace(tzinfo=None)
        start_time = end_time - timedelta(hours=1)

        features_table = os.getenv("FEATURES_TABLE", "features")
        features_columns = os.getenv("FEATURES_COLUMNS", "symbol,timestamp")
        query = f"""
            SELECT {features_columns}
            FROM {features_table}
            WHERE timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
              AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
        """

        result = self.client.query(query)
        if not result.result_rows:
            logger.info("No features data to validate")
            return

        col_names = [c.strip() for c in features_columns.split(",")]
        df = pd.DataFrame(result.result_rows, columns=col_names)

        suite = self._create_features_suite()
        checkpoint_result = self._validate_dataframe(df, suite, "features")
        self._store_validation_results("features", checkpoint_result, end_time)

    def _store_validation_results(
        self,
        data_type: str,
        checkpoint_result: Any,
        timestamp: datetime,
    ) -> None:
        """Store validation results to ClickHouse."""
        try:
            records = []

            try:
                for validation_result in checkpoint_result.run_results.values():
                    for exp_result in validation_result.results:
                        exp_type = type(exp_result.expectation_config).__name__
                        success = exp_result.success
                        records.append(
                            {
                                "timestamp": timestamp,
                                "data_type": data_type,
                                "expectation": exp_type,
                                "success": 1 if success else 0,
                                "details": str(exp_result.result)[:500],
                            }
                        )
            except (AttributeError, TypeError):
                results_dict = json.loads(checkpoint_result.describe())
                run_results = results_dict.get("run_results", {})
                for run_data in run_results.values():
                    validation_results = run_data.get("validation_result", {})
                    for exp in validation_results.get("results", []):
                        exp_config = exp.get("expectation_config", {})
                        records.append(
                            {
                                "timestamp": timestamp,
                                "data_type": data_type,
                                "expectation": exp_config.get("type", "unknown"),
                                "success": 1 if exp.get("success", False) else 0,
                                "details": str(exp.get("result", {}))[:500],
                            }
                        )

            if records:
                results_df = pd.DataFrame(records)
                # Writes land on the Null-engine staging table `features.quality_write_buffer`;
                # a MaterializedView funnels rows into `gold.data_quality_expectations`.
                # The `features.data_quality_expectations` name is a read-only View and
                # rejects INSERTs with "Method write is not supported by storage View".
                self.client.insert(
                    "quality_write_buffer",
                    results_df.values.tolist(),
                    column_names=list(results_df.columns),
                )
                logger.info(f"Stored {len(records)} validation results for {data_type}")

        except Exception as e:
            logger.error(f"Failed to store validation results: {e}")


class SimplifiedExpectationsRunner:
    """
    Simplified expectations runner that doesn't require full GE context.
    Uses config-driven column validation via environment variables.
    """

    def __init__(self) -> None:
        """Initialize runner."""
        self.client = self._get_client()

    def _get_client(self) -> Any:
        """Get ClickHouse client."""
        return clickhouse_connect.get_client(
            host=os.getenv("CLICKHOUSE_HOST", "clickhouse"),
            port=int(os.getenv("CLICKHOUSE_PORT", "8123")),
            database=os.getenv("CLICKHOUSE_DB", "features"),
            username=os.getenv("CLICKHOUSE_USER", "default"),
            password=os.getenv("CLICKHOUSE_PASSWORD", ""),
        )

    def run(self) -> None:
        """Run simplified expectations."""
        try:
            end_time = datetime.now(tz=UTC).replace(tzinfo=None)
            start_time = end_time - timedelta(hours=1)

            data_table = os.getenv("DATA_TABLE", "raw_data")
            data_columns = os.getenv("DATA_COLUMNS", "symbol,timestamp")
            query = f"""
                SELECT {data_columns}
                FROM {data_table}
                WHERE timestamp >= '{start_time.strftime("%Y-%m-%d %H:%M:%S")}'
                  AND timestamp < '{end_time.strftime("%Y-%m-%d %H:%M:%S")}'
            """

            result = self.client.query(query)
            if not result.result_rows:
                logger.info("No data to validate")
                return

            col_names = [c.strip() for c in data_columns.split(",")]
            df = pd.DataFrame(result.result_rows, columns=col_names)

            results = self._validate(df)
            self._store_results(results, end_time)

        except Exception as e:
            logger.error(f"Expectations failed: {e}")
            raise

    def _validate(self, df: pd.DataFrame) -> list:
        """Validate data with config-driven expectations."""
        results = []

        # Null checks on all columns
        for col in df.columns:
            null_count = df[col].isnull().sum()
            results.append(
                {
                    "expectation": f"expect_{col}_not_null",
                    "success": null_count == 0,
                    "observed_value": int(null_count),
                }
            )

        # Range checks on configured columns
        range_columns = _parse_csv_env("RANGE_CHECK_COLUMNS", "")
        range_max = float(os.getenv("RANGE_CHECK_MAX", "1000000"))
        for col in range_columns:
            if col in df.columns:
                min_val = df[col].min()
                max_val = df[col].max()
                results.append(
                    {
                        "expectation": f"expect_{col}_positive",
                        "success": min_val > 0,
                        "observed_value": float(min_val),
                    }
                )
                results.append(
                    {
                        "expectation": f"expect_{col}_reasonable",
                        "success": max_val < range_max,
                        "observed_value": float(max_val),
                    }
                )

        # Non-negative checks
        nonneg_columns = _parse_csv_env("NONNEG_COLUMNS", "")
        for col in nonneg_columns:
            if col in df.columns:
                min_val = df[col].min()
                results.append(
                    {
                        "expectation": f"expect_{col}_non_negative",
                        "success": min_val >= 0,
                        "observed_value": float(min_val),
                    }
                )

        # Pair comparison rules
        pair_rules = _parse_pair_rules("PAIR_RULES", "")
        for col_a, col_b in pair_rules:
            if col_a in df.columns and col_b in df.columns:
                invalid = (df[col_a] < df[col_b]).sum()
                results.append(
                    {
                        "expectation": f"expect_{col_a}_gte_{col_b}",
                        "success": invalid == 0,
                        "observed_value": int(invalid),
                    }
                )

        passed = sum(1 for r in results if r["success"])
        total = len(results)
        logger.info(f"Validation: {passed}/{total} passed")

        return results

    def _store_results(self, results: list, timestamp: datetime) -> None:
        """Store validation results."""
        try:
            records = []
            for r in results:
                records.append(
                    {
                        "timestamp": timestamp,
                        "data_type": os.getenv("DATA_TYPE", "raw"),
                        "expectation": r["expectation"],
                        "success": 1 if r["success"] else 0,
                        "details": str(r.get("observed_value", "")),
                    }
                )

            if records:
                df = pd.DataFrame(records)
                # See ExpectationsRunner._store_validation_results for the rationale:
                # target the Null-engine write buffer, not the read-only View.
                self.client.insert(
                    "quality_write_buffer",
                    df.values.tolist(),
                    column_names=list(df.columns),
                )
                logger.info(f"Stored {len(records)} results")

        except Exception as e:
            logger.error(f"Failed to store results: {e}")
