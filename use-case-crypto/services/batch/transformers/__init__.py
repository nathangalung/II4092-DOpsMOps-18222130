"""Crypto-specific technical analysis transformers.
Drop-in overlay for the generic transformers — exports same names.

Must re-export everything that the platform's features.py imports,
plus the crypto-specific compute_volatility_features.
The platform's temporal.py is kept as-is during overlay build.
"""

from .technical import (
    compute_technical_indicators,
    compute_volatility_features,
)
from .temporal import (
    compute_lag_features,
    compute_return_features,
    compute_target_features,
    compute_time_features,
)

# Re-export compute_dispersion_features as alias for compute_volatility_features.
# The platform's features.py imports this name; in the crypto overlay the equivalent
# functionality lives in compute_volatility_features (same signature, richer output).
compute_dispersion_features = compute_volatility_features

__all__ = [
    "compute_technical_indicators",
    "compute_volatility_features",
    "compute_dispersion_features",
    "compute_lag_features",
    "compute_return_features",
    "compute_target_features",
    "compute_time_features",
]
