"""Tests for PSI calculation."""

import numpy as np

from psi import calculate_psi, psi_interpretation


class TestCalculatePsi:
    def test_identical_distributions(self) -> None:
        """PSI should be ~0 for identical distributions."""
        data = np.random.randn(1000)
        psi = calculate_psi(data, data)
        assert psi < 0.01

    def test_similar_distributions(self) -> None:
        """PSI should be small for similar distributions."""
        ref = np.random.randn(1000)
        comp = np.random.randn(1000)
        psi = calculate_psi(ref, comp)
        assert psi < 0.1

    def test_different_distributions(self) -> None:
        """PSI should be large for different distributions."""
        ref = np.random.randn(1000)
        comp = np.random.randn(1000) + 5  # Shifted distribution
        psi = calculate_psi(ref, comp)
        assert psi > 0.25

    def test_small_sample_returns_zero(self) -> None:
        """PSI should return 0 for samples smaller than n_bins."""
        ref = np.array([1, 2, 3])
        comp = np.array([1, 2, 3])
        psi = calculate_psi(ref, comp, n_bins=10)
        assert psi == 0.0

    def test_custom_bins(self) -> None:
        """PSI should work with custom bin count."""
        ref = np.random.randn(500)
        comp = np.random.randn(500)
        psi = calculate_psi(ref, comp, n_bins=5)
        assert isinstance(psi, float)
        assert psi >= 0

    def test_returns_float(self) -> None:
        """PSI should return a float."""
        ref = np.random.randn(100)
        comp = np.random.randn(100)
        psi = calculate_psi(ref, comp)
        assert isinstance(psi, float)

    def test_non_negative(self) -> None:
        """PSI should always be non-negative."""
        for _ in range(10):
            ref = np.random.randn(100)
            comp = np.random.randn(100) * 2
            psi = calculate_psi(ref, comp)
            assert psi >= 0


class TestPsiInterpretation:
    def test_no_significant_change(self) -> None:
        assert psi_interpretation(0.05) == "no_significant_change"
        assert psi_interpretation(0.09) == "no_significant_change"

    def test_moderate_change(self) -> None:
        assert psi_interpretation(0.15) == "moderate_change"
        assert psi_interpretation(0.24) == "moderate_change"

    def test_significant_change(self) -> None:
        assert psi_interpretation(0.30) == "significant_change"
        assert psi_interpretation(0.50) == "significant_change"

    def test_boundary_values(self) -> None:
        assert psi_interpretation(0.1) == "moderate_change"
        assert psi_interpretation(0.25) == "significant_change"
