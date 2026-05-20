"""Tests for batch processing jobs."""

from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import numpy as np
import pandas as pd
import pytest

from config import Config
from jobs.backfill import BackfillJob
from jobs.features import FeatureEngineeringJob


@pytest.fixture
def mock_config() -> Config:
    """Mock configuration."""
    return Config(
        project_name="test",
        timezone="UTC",
        symbols=["SYMBOL-A", "SYMBOL-B"],
        enabled=True,
        schedule="0 * * * *",
        backfill_enabled=True,
        data_columns=["value_1", "value_2", "value_3", "value_4", "value_5"],
        technical_indicators={"moving_averages": {"rolling_mean": [7, 14]}},
        time_features_enabled=True,
        lag_columns=["value_4", "value_5"],
        lag_periods=[1, 6],
        return_periods=[1, 6],
        return_column="value_4",
        target_horizons=[1],
        target_column="value_4",
        dispersion_windows=[1, 24],
        clickhouse_host="localhost",
        clickhouse_port=8123,
        clickhouse_database="test",
        kafka_brokers="localhost:9092",
        kafka_topic_raw="raw",
        kafka_topic_features="features",
        train_start="2024-01-01T00:00:00",
        train_end="2024-06-01T00:00:00",
        validation_start="2024-06-01T00:00:00",
        validation_end="2024-07-01T00:00:00",
    )


@pytest.fixture
def sample_data() -> pd.DataFrame:
    """Sample time-series data for testing."""
    np.random.seed(42)
    n = 200
    base = 100 + np.cumsum(np.random.randn(n) * 2)
    return pd.DataFrame(
        {
            "symbol": ["SYMBOL-A"] * n,
            "timestamp": pd.date_range("2024-01-01", periods=n, freq="1h"),
            "value_1": base + np.random.randn(n) * 1,
            "value_2": base + np.abs(np.random.randn(n) * 2),
            "value_3": base - np.abs(np.random.randn(n) * 2),
            "value_4": base,
            "value_5": np.random.randint(1000, 10000, n).astype(float),
        }
    )


class TestFeatureEngineeringJob:
    def test_init(self, mock_config: Config) -> None:
        job = FeatureEngineeringJob(mock_config)
        assert job.config == mock_config
        assert job.client is None

    @patch("jobs.features.clickhouse_connect")
    def test_connect(self, mock_ch: MagicMock, mock_config: Config) -> None:
        job = FeatureEngineeringJob(mock_config)
        job.connect()

        mock_ch.get_client.assert_called_once_with(
            host="localhost",
            port=8123,
            database="test",
        )
        assert job.client is not None

    @patch("jobs.features.clickhouse_connect")
    def test_run_default_time_range(
        self, mock_ch: MagicMock, mock_config: Config, sample_data: pd.DataFrame
    ) -> None:
        """Test run with default time range (last 24 hours)."""
        mock_client = MagicMock()
        mock_ch.get_client.return_value = mock_client

        # Mock query result
        mock_result = MagicMock()
        mock_result.result_rows = sample_data.values.tolist()
        mock_client.query.return_value = mock_result

        job = FeatureEngineeringJob(mock_config)
        job.run()

        # Should query for each symbol
        assert mock_client.query.call_count >= 2  # SYMBOL-A and SYMBOL-B

    @patch("jobs.features.clickhouse_connect")
    def test_run_custom_time_range(
        self, mock_ch: MagicMock, mock_config: Config, sample_data: pd.DataFrame
    ) -> None:
        """Test run with custom time range."""
        mock_client = MagicMock()
        mock_ch.get_client.return_value = mock_client

        mock_result = MagicMock()
        mock_result.result_rows = sample_data.values.tolist()
        mock_client.query.return_value = mock_result

        job = FeatureEngineeringJob(mock_config)
        start = datetime(2024, 1, 1)
        end = datetime(2024, 1, 2)
        job.run(start_time=start, end_time=end)

        assert mock_client.query.called

    @patch("jobs.features.clickhouse_connect")
    def test_process_symbol_empty_data(
        self, mock_ch: MagicMock, mock_config: Config
    ) -> None:
        """Test handling of empty data."""
        mock_client = MagicMock()
        mock_ch.get_client.return_value = mock_client

        mock_result = MagicMock()
        mock_result.result_rows = []
        mock_client.query.return_value = mock_result

        job = FeatureEngineeringJob(mock_config)
        job.connect()

        # Should not raise, just log warning
        job._process_symbol(
            "SYMBOL-A", datetime.now() - timedelta(hours=24), datetime.now()
        )
        mock_client.insert.assert_not_called()

    def test_compute_all_features(
        self, mock_config: Config, sample_data: pd.DataFrame
    ) -> None:
        """Test feature computation."""
        job = FeatureEngineeringJob(mock_config)
        result = job._compute_all_features(sample_data)

        # Should have technical indicators
        assert "rolling_mean_7" in result.columns
        assert "rolling_mean_14" in result.columns

        # Should have time features
        assert "hour_of_day" in result.columns

        # Should have lag features
        assert "value_4_lag_1h" in result.columns

        # Should have return features
        assert "return_1h" in result.columns

        # Should have target features
        assert "target_return_1h" in result.columns

    @patch("jobs.features.clickhouse_connect")
    def test_close(self, mock_ch: MagicMock, mock_config: Config) -> None:
        """Test connection closing."""
        mock_client = MagicMock()
        mock_ch.get_client.return_value = mock_client

        job = FeatureEngineeringJob(mock_config)
        job.connect()
        job.close()

        mock_client.close.assert_called_once()
        assert job.client is None


class TestBackfillJob:
    def test_init(self, mock_config: Config) -> None:
        job = BackfillJob(mock_config)
        assert job.config == mock_config
        assert isinstance(job.feature_job, FeatureEngineeringJob)

    @patch.object(FeatureEngineeringJob, "connect")
    @patch.object(FeatureEngineeringJob, "run")
    @patch.object(FeatureEngineeringJob, "close")
    def test_run_default_dates(
        self,
        mock_close: MagicMock,
        mock_run: MagicMock,
        mock_connect: MagicMock,
        mock_config: Config,
    ) -> None:
        """Test run with default dates from config."""
        job = BackfillJob(mock_config)
        job.run()

        mock_connect.assert_called_once()
        mock_run.assert_called()  # Called multiple times for chunks
        mock_close.assert_called_once()

    @patch.object(FeatureEngineeringJob, "connect")
    @patch.object(FeatureEngineeringJob, "run")
    @patch.object(FeatureEngineeringJob, "close")
    def test_run_custom_dates(
        self,
        mock_close: MagicMock,
        mock_run: MagicMock,
        mock_connect: MagicMock,
        mock_config: Config,
    ) -> None:
        """Test run with custom dates."""
        job = BackfillJob(mock_config)
        start = datetime(2024, 1, 1)
        end = datetime(2024, 1, 15)
        job.run(start_time=start, end_time=end, chunk_days=7)

        mock_connect.assert_called_once()
        # Should be called twice (2 chunks for 14 days with 7-day chunks)
        assert mock_run.call_count == 2
        mock_close.assert_called_once()

    @patch.object(FeatureEngineeringJob, "connect")
    @patch.object(FeatureEngineeringJob, "run")
    @patch.object(FeatureEngineeringJob, "close")
    def test_run_chunk_processing(
        self,
        mock_close: MagicMock,
        mock_run: MagicMock,
        mock_connect: MagicMock,
        mock_config: Config,
    ) -> None:
        """Test chunked processing."""
        job = BackfillJob(mock_config)
        start = datetime(2024, 1, 1)
        end = datetime(2024, 1, 22)  # 21 days
        job.run(start_time=start, end_time=end, chunk_days=7)

        # 21 days / 7 days per chunk = 3 chunks
        assert mock_run.call_count == 3

    @patch.object(FeatureEngineeringJob, "connect")
    @patch.object(FeatureEngineeringJob, "run")
    @patch.object(FeatureEngineeringJob, "close")
    def test_run_incremental(
        self,
        mock_close: MagicMock,
        mock_run: MagicMock,
        mock_connect: MagicMock,
        mock_config: Config,
    ) -> None:
        """Test incremental backfill."""
        job = BackfillJob(mock_config)
        job.run_incremental(hours=48)

        mock_connect.assert_called_once()
        mock_run.assert_called_once()
        mock_close.assert_called_once()

        # Verify time range
        call_args = mock_run.call_args
        start_time = call_args[1]["start_time"]
        end_time = call_args[1]["end_time"]
        assert (end_time - start_time).total_seconds() == 48 * 3600

    @patch.object(FeatureEngineeringJob, "connect")
    @patch.object(FeatureEngineeringJob, "run")
    @patch.object(FeatureEngineeringJob, "close")
    def test_run_handles_errors(
        self,
        mock_close: MagicMock,
        mock_run: MagicMock,
        mock_connect: MagicMock,
        mock_config: Config,
    ) -> None:
        """Test error handling during chunk processing."""
        mock_run.side_effect = [Exception("Test error"), None]

        job = BackfillJob(mock_config)
        start = datetime(2024, 1, 1)
        end = datetime(2024, 1, 15)

        # Should not raise, continues with next chunk
        job.run(start_time=start, end_time=end, chunk_days=7)

        mock_close.assert_called_once()
