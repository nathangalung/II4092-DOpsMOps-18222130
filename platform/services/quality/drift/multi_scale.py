"""
Multi-scale drift detector.
Implements adaptive thresholds per time scale.
"""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import numpy as np

from ks_test import ks_test
from psi import calculate_psi


@dataclass
class DriftResult:
    """Drift detection result"""

    scale: str
    feature: str
    psi_value: float
    ks_statistic: float
    ks_pvalue: float
    drift_detected: bool
    severity: str  # 'none', 'warning', 'severe'
    trigger_retrain: bool


class MultiScaleDriftDetector:
    """Multi-scale drift detection with adaptive thresholds"""

    SCALES = {
        "minute": {"ref": 60, "comp": 1},  # 60 min ref, 1 min comp
        "hour": {"ref": 1440, "comp": 60},  # 24h ref, 1h comp
        "six_hour": {"ref": 10080, "comp": 360},  # 7d ref, 6h comp
        "twelve_hour": {"ref": 20160, "comp": 720},  # 14d ref, 12h comp
        "daily": {"ref": 43200, "comp": 1440},  # 30d ref, 24h comp
        "weekly": {"ref": 129600, "comp": 10080},  # 90d ref, 7d comp
        "monthly": {"ref": 525600, "comp": 43200},  # 365d ref, 30d comp
        "quarterly": {"ref": 1051200, "comp": 129600},  # 2y ref, 90d comp
    }

    def __init__(self, config: dict) -> None:
        self.config = config
        self.scales_config = config.get("scales", {})
        self.features = config.get("features_to_monitor", [])

    def check_drift(
        self,
        scale: str,
        feature: str,
        reference_data: np.ndarray,
        comparison_data: np.ndarray,
    ) -> DriftResult:
        """Check drift for single feature at given scale"""

        scale_cfg = self.scales_config.get(scale, {})
        psi_warning = scale_cfg.get("psi_warning", 0.1)
        psi_severe = scale_cfg.get("psi_severe", 0.25)
        ks_threshold = scale_cfg.get("ks_pvalue", 0.05)
        trigger = scale_cfg.get("trigger_retrain", True)

        # Calculate metrics
        psi = calculate_psi(reference_data, comparison_data)
        ks_stat, ks_pvalue = ks_test(reference_data, comparison_data)

        # Determine severity
        if psi > psi_severe or ks_pvalue < ks_threshold:
            severity = "severe"
            drift_detected = True
        elif psi > psi_warning:
            severity = "warning"
            drift_detected = True
        else:
            severity = "none"
            drift_detected = False

        return DriftResult(
            scale=scale,
            feature=feature,
            psi_value=psi,
            ks_statistic=ks_stat,
            ks_pvalue=ks_pvalue,
            drift_detected=drift_detected,
            severity=severity,
            trigger_retrain=drift_detected and trigger,
        )

    def check_all_scales(
        self, feature: str, data_getter: Callable[[str, str], tuple[Any, Any]]
    ) -> list[DriftResult]:
        """Check drift across all scales"""
        results = []

        for scale_name in self.scales_config:
            try:
                ref_data, comp_data = data_getter(scale_name, feature)
                result = self.check_drift(scale_name, feature, ref_data, comp_data)
                results.append(result)
            except Exception:
                continue

        return results
