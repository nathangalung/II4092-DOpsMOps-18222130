//! Generic bounds checking — columns and thresholds configured per use-case.

use crate::config::BoundsConfig;
use simd_json::prelude::{ValueAsScalar, ValueObjectAccess};

pub struct BoundsChecker {
    range_check_columns: Vec<String>,
    range_min: f64,
    range_max: f64,
    nonneg_columns: Vec<String>,
}

impl BoundsChecker {
    pub fn new(cfg: &BoundsConfig) -> Self {
        let range_check_columns: Vec<String> = cfg
            .range_check_columns
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        let nonneg_columns: Vec<String> = cfg
            .nonneg_columns
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        Self {
            range_check_columns,
            range_min: cfg.range_min,
            range_max: cfg.range_max,
            nonneg_columns,
        }
    }

    /// Check value bounds for configured columns.
    pub fn check(&self, v: &simd_json::OwnedValue) -> bool {
        // Check range-bounded columns
        for field in &self.range_check_columns {
            if let Some(val) = v.get(field.as_str()).and_then(|p| p.as_f64())
                && (val < self.range_min || val > self.range_max)
            {
                return false;
            }
        }

        // Check non-negative columns
        for field in &self.nonneg_columns {
            if let Some(val) = v.get(field.as_str()).and_then(|v| v.as_f64())
                && val < 0.0
            {
                return false;
            }
        }

        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bounds_valid_values() {
        let config = BoundsConfig {
            range_check_columns: "value_a,value_b".to_string(),
            range_min: 0.0,
            range_max: 100000.0,
            nonneg_columns: "count".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        let value = simd_json::json!({
            "value_a": 500.0,
            "value_b": 1000.0,
            "count": 100.0
        });
        assert!(checker.check(&value));
    }

    #[test]
    fn test_bounds_value_too_low() {
        let config = BoundsConfig {
            range_check_columns: "value_a".to_string(),
            range_min: 100.0,
            range_max: 100000.0,
            nonneg_columns: "".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        let value = simd_json::json!({ "value_a": 50.0 });
        assert!(!checker.check(&value));
    }

    #[test]
    fn test_bounds_value_too_high() {
        let config = BoundsConfig {
            range_check_columns: "value_a".to_string(),
            range_min: 0.0,
            range_max: 1000.0,
            nonneg_columns: "".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        let value = simd_json::json!({ "value_a": 2000.0 });
        assert!(!checker.check(&value));
    }

    #[test]
    fn test_bounds_nonneg_violation() {
        let config = BoundsConfig {
            range_check_columns: "".to_string(),
            range_min: 0.0,
            range_max: 100000.0,
            nonneg_columns: "count".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        let value = simd_json::json!({ "count": -5.0 });
        assert!(!checker.check(&value));
    }

    #[test]
    fn test_bounds_at_limits() {
        let config = BoundsConfig {
            range_check_columns: "value_a".to_string(),
            range_min: 100.0,
            range_max: 1000.0,
            nonneg_columns: "count".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        let value = simd_json::json!({ "value_a": 100.0, "count": 0.0 });
        assert!(checker.check(&value));
    }

    #[test]
    fn test_bounds_empty_columns() {
        let config = BoundsConfig {
            range_check_columns: "".to_string(),
            range_min: 0.0,
            range_max: 100000.0,
            nonneg_columns: "".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        // No columns configured = always passes
        let value = simd_json::json!({ "anything": 999999.0 });
        assert!(checker.check(&value));
    }

    #[test]
    fn test_bounds_missing_field() {
        let config = BoundsConfig {
            range_check_columns: "value_a,value_b".to_string(),
            range_min: 0.0,
            range_max: 100000.0,
            nonneg_columns: "".to_string(),
        };
        let checker = BoundsChecker::new(&config);

        // Missing value_b — just skips it (permissive)
        let value = simd_json::json!({ "value_a": 500.0 });
        assert!(checker.check(&value));
    }
}
