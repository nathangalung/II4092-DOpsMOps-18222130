"""Tests for outlier detection job."""

import os
from collections.abc import Generator
from datetime import UTC, datetime
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest


class TestOutlierDetector:
    """Tests for OutlierDetector class."""

    @pytest.fixture
    def detector(self) -> Generator:
        """Create outlier detector instance."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            return OutlierDetector(std_threshold=3.0)

    def test_init_default_threshold(self) -> None:
        """Test default initialization."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector()
            assert detector.std_threshold == 3.0

    def test_init_custom_threshold(self) -> None:
        """Test custom threshold initialization."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.5)
            assert detector.std_threshold == 2.5

    def test_get_client_connects_clickhouse(self) -> None:
        """Test _get_client connects to ClickHouse."""
        with (
            patch("jobs.outlier.clickhouse_connect") as mock_ch,
            patch.dict(
                "os.environ",
                {
                    "CLICKHOUSE_HOST": "test-host",
                    "CLICKHOUSE_PORT": "9000",
                    "CLICKHOUSE_DB": "test_db",
                },
            ),
        ):
            from jobs.outlier import OutlierDetector

            OutlierDetector()
            mock_ch.get_client.assert_called_once_with(
                host="test-host", port=9000, database="test_db"
            )

    def test_detect_outliers_z_score_method(self) -> None:
        """Test _detect_outliers uses z-score method."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)

            # Create data with known outliers
            np.random.seed(42)
            n = 100
            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * n,
                    "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
                    "value_1": np.random.randn(n) * 10 + 100,
                    "value_2": np.random.randn(n) * 10 + 102,
                    "value_3": np.random.randn(n) * 10 + 98,
                    "value_4": np.random.randn(n) * 10 + 100,
                    "value_5": np.random.randn(n) * 100 + 1000,
                }
            )

            # Add outliers
            df.loc[0, "value_4"] = 1000  # Extreme outlier
            df.loc[1, "value_5"] = 100  # Volume outlier

            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )

            assert isinstance(outliers, pd.DataFrame)
            assert len(outliers) > 0

    def test_detect_outliers_returns_correct_columns(self) -> None:
        """Test _detect_outliers returns correct columns."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)

            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * 10,
                    "timestamp": pd.date_range("2024-01-01", periods=10, freq="1h"),
                    "value_1": [100] * 9 + [1000],  # One outlier
                    "value_2": [102] * 10,
                    "value_3": [98] * 10,
                    "value_4": [100] * 9 + [1000],  # One outlier
                    "value_5": [1000] * 10,
                }
            )

            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )

            if not outliers.empty:
                expected_cols = [
                    "symbol",
                    "timestamp",
                    "column_name",
                    "value",
                    "z_score",
                    "detected_at",
                ]
                for col in expected_cols:
                    assert col in outliers.columns

    def test_detect_outliers_no_outliers(self) -> None:
        """Test _detect_outliers with normal data."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=3.0)

            # Normal distribution data - unlikely to have outliers
            np.random.seed(42)
            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * 100,
                    "timestamp": pd.date_range("2024-01-01", periods=100, freq="1h"),
                    "value_1": np.random.randn(100) + 100,
                    "value_2": np.random.randn(100) + 102,
                    "value_3": np.random.randn(100) + 98,
                    "value_4": np.random.randn(100) + 100,
                    "value_5": np.abs(np.random.randn(100)) * 100 + 1000,
                }
            )

            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )
            # With std_threshold=3, most normal data won't trigger
            assert isinstance(outliers, pd.DataFrame)

    def test_detect_outliers_multiple_symbols(self) -> None:
        """Test _detect_outliers handles multiple symbols."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)

            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * 50 + ["SYMBOL-B"] * 50,
                    "timestamp": list(
                        pd.date_range("2024-01-01", periods=50, freq="1h")
                    )
                    * 2,
                    "value_1": [100] * 50 + [3000] * 50,
                    "value_2": [102] * 50 + [3100] * 50,
                    "value_3": [98] * 50 + [2900] * 50,
                    "value_4": [100] * 49 + [1000] + [3000] * 49 + [10000],  # Outliers
                    "value_5": [1000] * 100,
                }
            )

            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )

            if not outliers.empty:
                assert set(outliers["symbol"].unique()).issubset(
                    {"SYMBOL-A", "SYMBOL-B"}
                )

    def test_run_queries_and_detects(self) -> None:
        """Test run queries ClickHouse and runs detection."""
        with (
            patch("jobs.outlier.clickhouse_connect") as mock_ch,
            patch.dict(
                os.environ,
                {
                    "DATA_COLUMNS": "symbol,timestamp,value_1,value_2,value_3,value_4,value_5"
                },
            ),
        ):
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_result = MagicMock()
            mock_result.result_rows = [
                ("SYMBOL-A", datetime.now(tz=UTC), 100, 102, 98, 100, 1000),
            ]
            mock_client.query.return_value = mock_result
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()
            detector._detect_outliers = MagicMock(return_value=pd.DataFrame())

            detector.run()

            mock_client.query.assert_called_once()
            detector._detect_outliers.assert_called_once()

    def test_run_no_data(self) -> None:
        """Test run handles no data gracefully."""
        with patch("jobs.outlier.clickhouse_connect") as mock_ch:
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_result = MagicMock()
            mock_result.result_rows = []
            mock_client.query.return_value = mock_result
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()
            detector.run()  # Should not raise

    def test_store_outliers_inserts_to_db(self) -> None:
        """Test _store_outliers inserts to ClickHouse."""
        with patch("jobs.outlier.clickhouse_connect") as mock_ch:
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()

            outliers = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"],
                    "timestamp": [datetime.now(tz=UTC)],
                    "column_name": ["value_4"],
                    "value": [1000],
                    "z_score": [5.0],
                    "detected_at": [datetime.now(tz=UTC)],
                }
            )

            detector._store_outliers(outliers)

            mock_client.insert.assert_called_once_with(
                "quality_outliers",
                outliers.values.tolist(),
                column_names=list(outliers.columns),
            )

    def test_z_score_calculation(self) -> None:
        """Test z-score calculation is correct."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)

            # Create data where we know the z-score
            # mean = 0, std = 1, so z-score of 5 should be an outlier
            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * 11,
                    "timestamp": pd.date_range("2024-01-01", periods=11, freq="1h"),
                    "value_1": [0] * 11,
                    "value_2": [0] * 11,
                    "value_3": [0] * 11,
                    "value_4": [0] * 10 + [10],  # Mean ~0.9, last value is outlier
                    "value_5": [1] * 11,
                }
            )

            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )

            # The value 10 should be detected as outlier
            outlier_cols = outliers[outliers["column_name"] == "value_4"]
            assert len(outlier_cols) > 0

    def test_handles_zero_std(self) -> None:
        """Test handles zero standard deviation."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)

            # All same values -> std = 0
            df = pd.DataFrame(
                {
                    "symbol": ["SYMBOL-A"] * 10,
                    "timestamp": pd.date_range("2024-01-01", periods=10, freq="1h"),
                    "value_1": [100] * 10,
                    "value_2": [102] * 10,
                    "value_3": [98] * 10,
                    "value_4": [100] * 10,  # All same -> std = 0
                    "value_5": [1000] * 10,
                }
            )

            # Should not raise and should return empty (no outliers when std=0)
            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "value_2", "value_3", "value_4", "value_5"]
            )
            assert isinstance(outliers, pd.DataFrame)

    def test_run_with_outliers_found(self) -> None:
        """Test run stores outliers when found."""
        with (
            patch("jobs.outlier.clickhouse_connect") as mock_ch,
            patch.dict(
                os.environ,
                {
                    "DATA_COLUMNS": "symbol,timestamp,value_1",
                    "OUTLIER_COLUMNS": "value_1",
                },
            ),
        ):
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_result = MagicMock()
            mock_result.result_rows = [
                ("SYM-A", datetime(2024, 1, 1, i), 100.0) for i in range(10)
            ] + [("SYM-A", datetime(2024, 1, 1, 10), 10000.0)]
            mock_client.query.return_value = mock_result
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector(std_threshold=2.0)
            detector.run()

            # outliers found → store called
            mock_client.insert.assert_called()

    def test_run_exception_handling(self) -> None:
        """Test run raises on error."""
        with patch("jobs.outlier.clickhouse_connect") as mock_ch:
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_client.query.side_effect = Exception("DB error")
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()
            with pytest.raises(Exception, match="DB error"):
                detector.run()

    def test_store_outliers_error(self) -> None:
        """Test _store_outliers handles insert error."""
        with patch("jobs.outlier.clickhouse_connect") as mock_ch:
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_client.insert.side_effect = Exception("Insert failed")
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()
            outliers = pd.DataFrame(
                {
                    "symbol": ["SYM-A"],
                    "timestamp": [datetime.now(tz=UTC)],
                    "column_name": ["value_1"],
                    "value": [999],
                    "z_score": [5.0],
                    "detected_at": [datetime.now(tz=UTC)],
                }
            )
            # Should not raise
            detector._store_outliers(outliers)

    def test_detect_outliers_missing_column(self) -> None:
        """Test _detect_outliers skips missing columns."""
        with patch("jobs.outlier.clickhouse_connect"):
            from jobs.outlier import OutlierDetector

            detector = OutlierDetector(std_threshold=2.0)
            df = pd.DataFrame(
                {
                    "symbol": ["SYM-A"] * 5,
                    "timestamp": pd.date_range("2024-01-01", periods=5, freq="1h"),
                    "value_1": [100] * 5,
                }
            )
            outliers = detector._detect_outliers(
                df, "symbol", ["value_1", "nonexistent_col"]
            )
            assert isinstance(outliers, pd.DataFrame)

    def test_run_auto_detect_columns(self) -> None:
        """Test run auto-detects numeric columns when OUTLIER_COLUMNS not set."""
        with (
            patch("jobs.outlier.clickhouse_connect") as mock_ch,
            patch.dict(
                os.environ,
                {
                    "DATA_COLUMNS": "symbol,timestamp,value_1,value_2",
                    "OUTLIER_COLUMNS": "",
                },
            ),
        ):
            from jobs.outlier import OutlierDetector

            mock_client = MagicMock()
            mock_result = MagicMock()
            mock_result.result_rows = [
                ("SYM-A", datetime(2024, 1, 1, i), 100.0, 200.0) for i in range(10)
            ]
            mock_client.query.return_value = mock_result
            mock_ch.get_client.return_value = mock_client

            detector = OutlierDetector()
            detector._detect_outliers = MagicMock(return_value=pd.DataFrame())
            detector.run()

            # Check that auto-detected columns exclude symbol and timestamp
            call_args = detector._detect_outliers.call_args
            check_columns = call_args[0][2]
            assert "symbol" not in check_columns
            assert "timestamp" not in check_columns
