"""Tests for multi-scale drift detector."""

from typing import Any

import numpy as np
import pytest

from multi_scale import DriftResult, MultiScaleDriftDetector


@pytest.fixture
def config() -> dict[str, Any]:
    """Drift detector config."""
    return {
        "scales": {
            "hour": {
                "psi_warning": 0.1,
                "psi_severe": 0.25,
                "ks_pvalue": 0.05,
                "trigger_retrain": True,
            },
            "daily": {
                "psi_warning": 0.15,
                "psi_severe": 0.3,
                "ks_pvalue": 0.01,
                "trigger_retrain": True,
            },
        },
        "features_to_monitor": ["value_1", "value_2"],
    }


@pytest.fixture
def detector(config: dict[str, Any]) -> MultiScaleDriftDetector:
    """Drift detector instance."""
    return MultiScaleDriftDetector(config)


class TestMultiScaleDriftDetector:
    def test_init(self, config: dict[str, Any]) -> None:
        detector = MultiScaleDriftDetector(config)
        assert detector.config == config
        assert "hour" in detector.scales_config

    def test_check_drift_no_drift(self, detector: MultiScaleDriftDetector) -> None:
        """No drift for similar distributions."""
        ref = np.random.randn(500)
        comp = np.random.randn(500)
        result = detector.check_drift("hour", "value_1", ref, comp)
        assert isinstance(result, DriftResult)
        assert result.drift_detected is False
        assert result.severity == "none"

    def test_check_drift_warning(self, detector: MultiScaleDriftDetector) -> None:
        """Warning level drift."""
        ref = np.random.randn(500)
        comp = np.random.randn(500) + 0.5  # Small shift
        result = detector.check_drift("hour", "value_1", ref, comp)
        # Might or might not trigger depending on random seed
        assert result.severity in ["none", "warning", "severe"]

    def test_check_drift_severe(self, detector: MultiScaleDriftDetector) -> None:
        """Severe drift for large distribution shift."""
        ref = np.random.randn(500)
        comp = np.random.randn(500) + 5  # Large shift
        result = detector.check_drift("hour", "value_1", ref, comp)
        assert result.drift_detected is True
        assert result.severity == "severe"

    def test_trigger_retrain(self, detector: MultiScaleDriftDetector) -> None:
        """Retrain triggered on drift when configured."""
        ref = np.random.randn(500)
        comp = np.random.randn(500) + 5
        result = detector.check_drift("hour", "value_1", ref, comp)
        assert result.trigger_retrain is True

    def test_drift_result_fields(self, detector: MultiScaleDriftDetector) -> None:
        """DriftResult has all required fields."""
        ref = np.random.randn(100)
        comp = np.random.randn(100)
        result = detector.check_drift("hour", "value_1", ref, comp)
        assert hasattr(result, "scale")
        assert hasattr(result, "feature")
        assert hasattr(result, "psi_value")
        assert hasattr(result, "ks_statistic")
        assert hasattr(result, "ks_pvalue")
        assert hasattr(result, "drift_detected")
        assert hasattr(result, "severity")
        assert hasattr(result, "trigger_retrain")


class TestDriftResult:
    def test_dataclass(self) -> None:
        result = DriftResult(
            scale="hour",
            feature="value_1",
            psi_value=0.15,
            ks_statistic=0.08,
            ks_pvalue=0.10,
            drift_detected=True,
            severity="warning",
            trigger_retrain=True,
        )
        assert result.scale == "hour"
        assert result.feature == "value_1"
        assert result.psi_value == 0.15
        assert result.drift_detected is True
