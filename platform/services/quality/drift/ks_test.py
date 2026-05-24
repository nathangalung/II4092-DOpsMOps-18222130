"""
Kolmogorov-Smirnov test for distribution comparison.
Non-parametric test for distribution equality.
"""

import numpy as np
from scipy import stats


def ks_test(reference: np.ndarray, comparison: np.ndarray) -> tuple[float, float]:
    """
    Perform two-sample Kolmogorov-Smirnov test.

    Args:
        reference: Reference distribution data
        comparison: Comparison distribution data

    Returns:
        Tuple of (statistic, p-value)
    """
    if len(reference) < 5 or len(comparison) < 5:
        return 0.0, 1.0

    statistic, pvalue = stats.ks_2samp(reference, comparison)
    return float(statistic), float(pvalue)


def interpret_ks_result(pvalue: float, alpha: float = 0.05) -> bool:
    """
    Interpret KS test result.

    Returns:
        True if distributions are significantly different
    """
    return pvalue < alpha
