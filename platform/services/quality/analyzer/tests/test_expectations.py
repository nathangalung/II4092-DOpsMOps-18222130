"""Tests for expectations runner."""

import os
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

from jobs.expectations import (
    SimplifiedExpectationsRunner,
    _parse_csv_env,
    _parse_pair_rules,
)


class TestParseCsvEnv:
    def test_basic(self) -> None:
        with patch.dict(os.environ, {"TEST_CSV": "a,b,c"}):
            result = _parse_csv_env("TEST_CSV", "")
        assert result == ["a", "b", "c"]

    def test_default(self) -> None:
        result = _parse_csv_env("NONEXISTENT_KEY_123", "x,y")
        assert result == ["x", "y"]

    def test_empty(self) -> None:
        result = _parse_csv_env("NONEXISTENT_KEY_123", "")
        assert result == []

    def test_whitespace(self) -> None:
        with patch.dict(os.environ, {"TEST_CSV": " a , b , c "}):
            result = _parse_csv_env("TEST_CSV", "")
        assert result == ["a", "b", "c"]


class TestParsePairRules:
    def test_basic(self) -> None:
        with patch.dict(os.environ, {"TEST_PAIRS": "a>b,c>d"}):
            result = _parse_pair_rules("TEST_PAIRS", "")
        assert result == [("a", "b"), ("c", "d")]

    def test_empty(self) -> None:
        result = _parse_pair_rules("NONEXISTENT_KEY_123", "")
        assert result == []

    def test_whitespace(self) -> None:
        with patch.dict(os.environ, {"TEST_PAIRS": " a > b , c > d "}):
            result = _parse_pair_rules("TEST_PAIRS", "")
        assert result == [("a", "b"), ("c", "d")]

    def test_no_gt_skipped(self) -> None:
        with patch.dict(os.environ, {"TEST_PAIRS": "a>b,invalid"}):
            result = _parse_pair_rules("TEST_PAIRS", "")
        assert result == [("a", "b")]

    def test_default_value(self) -> None:
        result = _parse_pair_rules("NONEXISTENT_KEY_123", "x>y")
        assert result == [("x", "y")]


class TestExpectationsRunner:
    def test_init(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            mock_ch.get_client.assert_called_once()
            assert runner.client is not None

    def test_create_data_suite(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
            patch.dict(
                os.environ,
                {
                    "REQUIRED_COLUMNS": "symbol,timestamp,value",
                    "RANGE_CHECK_COLUMNS": "value",
                    "RANGE_CHECK_MIN": "0",
                    "RANGE_CHECK_MAX": "999",
                    "NONNEG_COLUMNS": "count",
                    "PAIR_RULES": "a>b",
                    "VALID_SYMBOLS": "SYM-A,SYM-B",
                    "ENTITY_COLUMN": "symbol",
                },
            ),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            suite = runner._create_data_suite()
            assert suite is not None

    def test_create_features_suite(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
            patch.dict(
                os.environ,
                {
                    "BOUNDED_FEATURES": "momentum:0:100,confidence:0:1",
                    "FEATURE_PAIR_RULES": "upper>lower",
                    "NONNEG_FEATURES": "dispersion",
                },
            ),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            suite = runner._create_features_suite()
            assert suite is not None

    def test_create_features_suite_empty_bounded(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
            patch.dict(os.environ, {"BOUNDED_FEATURES": ""}),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            suite = runner._create_features_suite()
            assert suite is not None

    def test_create_features_suite_malformed_bounded(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
            patch.dict(os.environ, {"BOUNDED_FEATURES": "bad_entry,also_bad"}),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            suite = runner._create_features_suite()
            assert suite is not None

    def test_validate_dataframe(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            df = pd.DataFrame({"a": [1, 2], "b": [3, 4]})
            suite = MagicMock()
            runner._validate_dataframe(df, suite, "test")

    def test_run(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            runner._validate_data = MagicMock()
            runner._validate_features = MagicMock()
            runner.run()

            runner._validate_data.assert_called_once()
            runner._validate_features.assert_called_once()

    def test_run_raises(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            runner = ExpectationsRunner()
            runner._validate_data = MagicMock(side_effect=Exception("fail"))

            with pytest.raises(Exception, match="fail"):
                runner.run()

    def test_validate_data(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
            patch.dict(os.environ, {"DATA_COLUMNS": "symbol,timestamp,value"}),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = [("SYM-A", datetime.now(tz=UTC), 100)]
            mock_client.query.return_value = mock_result

            runner = ExpectationsRunner()
            runner._validate_dataframe = MagicMock(return_value=MagicMock())
            runner._store_validation_results = MagicMock()
            runner._validate_data()

            mock_client.query.assert_called_once()
            runner._validate_dataframe.assert_called_once()

    def test_validate_data_no_data(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = []
            mock_client.query.return_value = mock_result

            runner = ExpectationsRunner()
            runner._validate_dataframe = MagicMock()
            runner._validate_data()

            runner._validate_dataframe.assert_not_called()

    def test_validate_features(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
            patch.dict(os.environ, {"FEATURES_COLUMNS": "symbol,timestamp,feature_a"}),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = [("SYM-A", datetime.now(tz=UTC), 0.5)]
            mock_client.query.return_value = mock_result

            runner = ExpectationsRunner()
            runner._validate_dataframe = MagicMock(return_value=MagicMock())
            runner._store_validation_results = MagicMock()
            runner._validate_features()

            runner._validate_dataframe.assert_called_once()

    def test_validate_features_no_data(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = []
            mock_client.query.return_value = mock_result

            runner = ExpectationsRunner()
            runner._validate_dataframe = MagicMock()
            runner._validate_features()

            runner._validate_dataframe.assert_not_called()

    def test_store_validation_results_object_api(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value

            # Mock checkpoint result with object API
            exp_result = MagicMock()
            exp_result.expectation_config = MagicMock()
            type(exp_result.expectation_config).__name__ = "ExpectColumnToExist"
            exp_result.success = True
            exp_result.result = {"observed_value": True}

            validation_result = MagicMock()
            validation_result.results = [exp_result]
            checkpoint_result = MagicMock()
            checkpoint_result.run_results = {"key1": validation_result}

            runner = ExpectationsRunner()
            runner._store_validation_results("raw", checkpoint_result, datetime.now(tz=UTC))

            mock_client.insert.assert_called_once()

    def test_store_validation_results_json_fallback(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value

            # Mock checkpoint result that fails object API
            checkpoint_result = MagicMock()
            checkpoint_result.run_results = MagicMock()
            checkpoint_result.run_results.values.side_effect = AttributeError

            import json

            describe_data = {
                "run_results": {
                    "key1": {
                        "validation_result": {
                            "results": [
                                {
                                    "expectation_config": {
                                        "type": "ExpectColumnToExist"
                                    },
                                    "success": True,
                                    "result": {},
                                }
                            ]
                        }
                    }
                }
            }
            checkpoint_result.describe.return_value = json.dumps(describe_data)

            runner = ExpectationsRunner()
            runner._store_validation_results("raw", checkpoint_result, datetime.now(tz=UTC))

            mock_client.insert.assert_called_once()

    def test_store_validation_results_error(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value
            mock_client.insert.side_effect = Exception("DB error")

            exp_result = MagicMock()
            exp_result.expectation_config = MagicMock()
            type(exp_result.expectation_config).__name__ = "Test"
            exp_result.success = True
            exp_result.result = {}
            validation_result = MagicMock()
            validation_result.results = [exp_result]
            checkpoint_result = MagicMock()
            checkpoint_result.run_results = {"key1": validation_result}

            runner = ExpectationsRunner()
            # Should not raise
            runner._store_validation_results("raw", checkpoint_result, datetime.now(tz=UTC))

    def test_store_validation_no_records(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect") as mock_ch,
            patch("jobs.expectations.gx"),
        ):
            from jobs.expectations import ExpectationsRunner

            mock_client = mock_ch.get_client.return_value

            checkpoint_result = MagicMock()
            checkpoint_result.run_results = {}

            runner = ExpectationsRunner()
            runner._store_validation_results("raw", checkpoint_result, datetime.now(tz=UTC))

            mock_client.insert.assert_not_called()


class TestSimplifiedExpectationsRunner:
    def test_init(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            runner = SimplifiedExpectationsRunner()
            mock_ch.get_client.assert_called_once()
            assert runner.client is not None

    def test_run(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = [("SYM-A", datetime.now(tz=UTC))]
            mock_client.query.return_value = mock_result

            runner = SimplifiedExpectationsRunner()
            runner._validate = MagicMock(return_value=[])
            runner._store_results = MagicMock()
            runner.run()

            runner._validate.assert_called_once()

    def test_run_no_data(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_client = mock_ch.get_client.return_value
            mock_result = MagicMock()
            mock_result.result_rows = []
            mock_client.query.return_value = mock_result

            runner = SimplifiedExpectationsRunner()
            runner._validate = MagicMock()
            runner.run()

            runner._validate.assert_not_called()

    def test_run_raises(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_ch.get_client.side_effect = Exception("connect fail")

            with pytest.raises(Exception, match="connect fail"):
                SimplifiedExpectationsRunner()

    def test_validate_null_checks(self) -> None:
        with patch("jobs.expectations.clickhouse_connect"):
            runner = SimplifiedExpectationsRunner()
            df = pd.DataFrame({"col_a": [1, 2, None], "col_b": [3, 4, 5]})
            results = runner._validate(df)

            null_results = [r for r in results if "not_null" in r["expectation"]]
            assert len(null_results) == 2
            col_a_result = next(r for r in null_results if "col_a" in r["expectation"])
            assert not col_a_result["success"]
            assert col_a_result["observed_value"] == 1

    def test_validate_range_checks(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch.dict(
                os.environ,
                {"RANGE_CHECK_COLUMNS": "value", "RANGE_CHECK_MAX": "100"},
            ),
        ):
            runner = SimplifiedExpectationsRunner()
            df = pd.DataFrame({"value": [10, 50, 200]})
            results = runner._validate(df)

            range_results = [r for r in results if "reasonable" in r["expectation"]]
            assert len(range_results) == 1
            assert not range_results[0]["success"]

    def test_validate_nonneg_checks(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch.dict(os.environ, {"NONNEG_COLUMNS": "count"}),
        ):
            runner = SimplifiedExpectationsRunner()
            df = pd.DataFrame({"count": [-1, 5, 10]})
            results = runner._validate(df)

            nonneg_results = [r for r in results if "non_negative" in r["expectation"]]
            assert len(nonneg_results) == 1
            assert not nonneg_results[0]["success"]

    def test_validate_pair_rules(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch.dict(os.environ, {"PAIR_RULES": "high>low"}),
        ):
            runner = SimplifiedExpectationsRunner()
            df = pd.DataFrame({"high": [10, 20], "low": [5, 15]})
            results = runner._validate(df)

            pair_results = [r for r in results if "gte" in r["expectation"]]
            assert len(pair_results) == 1
            assert pair_results[0]["success"]

    def test_validate_pair_rules_violation(self) -> None:
        with (
            patch("jobs.expectations.clickhouse_connect"),
            patch.dict(os.environ, {"PAIR_RULES": "high>low"}),
        ):
            runner = SimplifiedExpectationsRunner()
            df = pd.DataFrame({"high": [10, 5], "low": [5, 15]})
            results = runner._validate(df)

            pair_results = [r for r in results if "gte" in r["expectation"]]
            assert len(pair_results) == 1
            assert not pair_results[0]["success"]

    def test_store_results(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_client = mock_ch.get_client.return_value

            runner = SimplifiedExpectationsRunner()
            results = [
                {"expectation": "test_exp", "success": True, "observed_value": 0},
            ]
            runner._store_results(results, datetime.now(tz=UTC))

            mock_client.insert.assert_called_once()

    def test_store_results_empty(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_client = mock_ch.get_client.return_value

            runner = SimplifiedExpectationsRunner()
            runner._store_results([], datetime.now(tz=UTC))

            mock_client.insert.assert_not_called()

    def test_store_results_error(self) -> None:
        with patch("jobs.expectations.clickhouse_connect") as mock_ch:
            mock_client = mock_ch.get_client.return_value
            mock_client.insert.side_effect = Exception("DB error")

            runner = SimplifiedExpectationsRunner()
            results = [{"expectation": "test", "success": True, "observed_value": 0}]
            # Should not raise
            runner._store_results(results, datetime.now(tz=UTC))
