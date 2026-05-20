"""Tests for Kolmogorov-Smirnov test."""

import numpy as np

from ks_test import interpret_ks_result, ks_test


class TestKsTest:
    def test_identical_distributions(self) -> None:
        """Same distribution should have high p-value."""
        data = np.random.randn(100)
        stat, pvalue = ks_test(data, data)
        assert stat == 0.0
        assert pvalue == 1.0

    def test_similar_distributions(self) -> None:
        """Similar distributions should have high p-value."""
        np.random.seed(42)
        ref = np.random.randn(500)
        comp = np.random.randn(500)
        stat, pvalue = ks_test(ref, comp)
        assert pvalue > 0.05

    def test_different_distributions(self) -> None:
        """Different distributions should have low p-value."""
        ref = np.random.randn(500)
        comp = np.random.randn(500) + 3  # Shifted
        stat, pvalue = ks_test(ref, comp)
        assert pvalue < 0.05

    def test_small_sample(self) -> None:
        """Small samples should return default values."""
        ref = np.array([1, 2])
        comp = np.array([1, 2])
        stat, pvalue = ks_test(ref, comp)
        assert stat == 0.0
        assert pvalue == 1.0

    def test_returns_tuple(self) -> None:
        """Should return tuple of floats."""
        ref = np.random.randn(50)
        comp = np.random.randn(50)
        result = ks_test(ref, comp)
        assert isinstance(result, tuple)
        assert len(result) == 2
        assert isinstance(result[0], float)
        assert isinstance(result[1], float)

    def test_statistic_bounded(self) -> None:
        """KS statistic should be in [0, 1]."""
        ref = np.random.randn(100)
        comp = np.random.randn(100)
        stat, _ = ks_test(ref, comp)
        assert 0 <= stat <= 1

    def test_pvalue_bounded(self) -> None:
        """P-value should be in [0, 1]."""
        ref = np.random.randn(100)
        comp = np.random.randn(100)
        _, pvalue = ks_test(ref, comp)
        assert 0 <= pvalue <= 1


class TestInterpretKsResult:
    def test_significant_difference(self) -> None:
        assert interpret_ks_result(0.01) is True
        assert interpret_ks_result(0.04) is True

    def test_no_significant_difference(self) -> None:
        assert interpret_ks_result(0.10) is False
        assert interpret_ks_result(0.50) is False

    def test_boundary(self) -> None:
        assert interpret_ks_result(0.05) is False  # Equal to alpha
        assert interpret_ks_result(0.049) is True

    def test_custom_alpha(self) -> None:
        assert interpret_ks_result(0.05, alpha=0.10) is True
        assert interpret_ks_result(0.05, alpha=0.01) is False
