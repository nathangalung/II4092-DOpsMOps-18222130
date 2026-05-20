"""
Population Stability Index (PSI) calculation.
Measures distribution shift between reference and comparison.
"""

import numpy as np


def calculate_psi(reference: np.ndarray, comparison: np.ndarray, n_bins: int = 10) -> float:
    """
    Calculate PSI between reference and comparison distributions.

    Args:
        reference: Reference distribution data
        comparison: Comparison distribution data
        n_bins: Number of bins for discretization

    Returns:
        PSI value (0 = no shift, >0.25 = significant shift)
    """
    if len(reference) < n_bins or len(comparison) < n_bins:
        return 0.0

    # Create bins from reference distribution
    breakpoints = np.percentile(reference, np.linspace(0, 100, n_bins + 1))
    breakpoints = np.unique(breakpoints)

    if len(breakpoints) < 2:
        return 0.0

    # Calculate proportions
    ref_counts = np.histogram(reference, bins=breakpoints)[0]
    comp_counts = np.histogram(comparison, bins=breakpoints)[0]

    ref_pct = ref_counts / len(reference)
    comp_pct = comp_counts / len(comparison)

    # Avoid division by zero
    ref_pct = np.clip(ref_pct, 1e-10, 1)
    comp_pct = np.clip(comp_pct, 1e-10, 1)

    # PSI formula
    psi = np.sum((comp_pct - ref_pct) * np.log(comp_pct / ref_pct))

    return float(psi)


def psi_interpretation(psi: float) -> str:
    """Interpret PSI value"""
    if psi < 0.1:
        return "no_significant_change"
    elif psi < 0.25:
        return "moderate_change"
    else:
        return "significant_change"
