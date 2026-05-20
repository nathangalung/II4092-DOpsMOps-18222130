use super::indicators::*;
use crate::config::IndicatorConfig;

// Rolling Mean Tests
#[test]
fn test_rolling_mean_basic() {
    let values = vec![1.0, 2.0, 3.0, 4.0, 5.0];
    assert_eq!(compute_rolling_mean(&values, 5), 3.0);
}

#[test]
fn test_rolling_mean_partial_period() {
    let values = vec![1.0, 2.0, 3.0, 4.0, 5.0];
    assert_eq!(compute_rolling_mean(&values, 2), 4.5); // Average of last 2: (4+5)/2
}

#[test]
fn test_rolling_mean_insufficient_data() {
    let values = vec![1.0, 2.0];
    assert_eq!(compute_rolling_mean(&values, 5), 0.0);
}

#[test]
fn test_rolling_mean_single_value() {
    let values = vec![10.0];
    assert_eq!(compute_rolling_mean(&values, 1), 10.0);
}

#[test]
fn test_rolling_mean_empty() {
    let values: Vec<f64> = vec![];
    assert_eq!(compute_rolling_mean(&values, 5), 0.0);
}

// Exponential Average Tests
#[test]
fn test_exp_avg_basic() {
    let values = vec![10.0, 11.0, 12.0];
    let ema = compute_exp_avg(&values, 3);
    assert!((ema - 11.25).abs() < 0.01);
}

#[test]
fn test_exp_avg_single_value() {
    let values = vec![10.0];
    assert_eq!(compute_exp_avg(&values, 5), 10.0);
}

#[test]
fn test_exp_avg_empty() {
    let values: Vec<f64> = vec![];
    assert_eq!(compute_exp_avg(&values, 5), 0.0);
}

#[test]
fn test_exp_avg_constant_values() {
    let values = vec![10.0, 10.0, 10.0, 10.0, 10.0];
    assert_eq!(compute_exp_avg(&values, 5), 10.0);
}

#[test]
fn test_exp_avg_trending_up() {
    let values = vec![1.0, 2.0, 3.0, 4.0, 5.0];
    let ema = compute_exp_avg(&values, 3);
    assert!(ema > 2.0 && ema < 5.0);
}

// Momentum Tests
#[test]
fn test_momentum_all_gains() {
    let values = vec![10.0, 10.5, 11.0, 11.5, 12.0];
    let momentum = compute_momentum(&values, 4);
    assert!(momentum > 90.0);
}

#[test]
fn test_momentum_all_losses() {
    let values = vec![10.0, 9.5, 9.0, 8.5, 8.0];
    let momentum = compute_momentum(&values, 4);
    assert!(momentum < 10.0);
}

#[test]
fn test_momentum_mixed() {
    let values = vec![10.0, 11.0, 10.5, 11.5, 10.0];
    let momentum = compute_momentum(&values, 4);
    assert!(momentum > 20.0 && momentum < 80.0);
}

#[test]
fn test_momentum_insufficient_data() {
    let values = vec![10.0, 11.0];
    let momentum = compute_momentum(&values, 14);
    assert_eq!(momentum, 50.0);
}

#[test]
fn test_momentum_bounds() {
    let values = vec![10.0, 11.0, 12.0, 13.0, 14.0, 15.0];
    let momentum = compute_momentum(&values, 4);
    assert!(momentum >= 0.0 && momentum <= 100.0);
}

// Trend Convergence Tests
#[test]
fn test_trend_convergence_insufficient_data() {
    let values = vec![1.0; 10];
    let (convergence, signal, hist) = compute_trend_convergence(&values);
    assert_eq!(convergence, 0.0);
    assert_eq!(signal, 0.0);
    assert_eq!(hist, 0.0);
}

#[test]
fn test_trend_convergence_sufficient_data() {
    let values: Vec<f64> = (1..=30).map(|x| x as f64).collect();
    let (convergence, _signal, _hist) = compute_trend_convergence(&values);
    assert!(convergence != 0.0);
}

#[test]
fn test_trend_convergence_constant_values() {
    let values = vec![10.0; 30];
    let (convergence, _signal, _hist) = compute_trend_convergence(&values);
    assert!(f64::abs(convergence) < 0.01);
}

// Deviation Bands Tests
#[test]
fn test_deviation_bands_constant_values() {
    let values = vec![10.0, 10.0, 10.0, 10.0, 10.0];
    let (upper, mid, lower) = compute_deviation_bands(&values, 5);
    assert_eq!(mid, 10.0);
    assert_eq!(upper, 10.0);
    assert_eq!(lower, 10.0);
}

#[test]
fn test_deviation_bands_with_variance() {
    let values = vec![8.0, 9.0, 10.0, 11.0, 12.0];
    let (upper, mid, lower) = compute_deviation_bands(&values, 5);
    assert_eq!(mid, 10.0);
    assert!(upper > mid);
    assert!(lower < mid);
}

#[test]
fn test_deviation_bands_insufficient_data() {
    let values = vec![10.0, 11.0];
    let (upper, mid, lower) = compute_deviation_bands(&values, 5);
    assert_eq!(upper, 0.0);
    assert_eq!(mid, 0.0);
    assert_eq!(lower, 0.0);
}

#[test]
fn test_deviation_bands_symmetry() {
    let values = vec![8.0, 9.0, 10.0, 11.0, 12.0];
    let (upper, mid, lower) = compute_deviation_bands(&values, 5);
    let upper_dist: f64 = upper - mid;
    let lower_dist: f64 = mid - lower;
    assert!(f64::abs(upper_dist - lower_dist) < 0.0001);
}

// Dynamic Features tests
#[test]
fn test_compute_all_default_config() {
    let primary_values: Vec<f64> = (1..=30).map(|x| x as f64 * 100.0).collect();
    let secondary_values: Vec<f64> = vec![1000.0; 30];
    let config = IndicatorConfig {
        rolling_mean_periods: vec![7, 14, 30],
        exp_avg_periods: vec![12, 26],
        momentum_period: 14,
        trend_convergence_enabled: true,
        deviation_bands_period: 20,
        deviation_bands_enabled: true,
        secondary_avg_period: 14,
        dispersion_period: 14,
        window_size: 200,
    };

    let features = compute_all(&primary_values, &secondary_values, &config);

    assert!(features.contains_key("value"));
    assert!(features.contains_key("rolling_mean_7"));
    assert!(features.contains_key("rolling_mean_14"));
    assert!(features.contains_key("rolling_mean_30"));
    assert!(features.contains_key("rolling_ema_12"));
    assert!(features.contains_key("rolling_ema_26"));
    assert!(features.contains_key("momentum_14"));
    assert!(features.contains_key("trend_convergence"));
    assert!(features.contains_key("band_upper"));
    assert!(features.contains_key("secondary_avg"));
    assert!(features.contains_key("value_change"));
    assert!(features.contains_key("dispersion"));
}

#[test]
fn test_compute_all_custom_config() {
    let primary_values: Vec<f64> = (1..=30).map(|x| x as f64 * 100.0).collect();
    let secondary_values: Vec<f64> = vec![1000.0; 30];
    let config = IndicatorConfig {
        rolling_mean_periods: vec![5],
        exp_avg_periods: vec![10],
        momentum_period: 7,
        trend_convergence_enabled: false,
        deviation_bands_period: 10,
        deviation_bands_enabled: false,
        secondary_avg_period: 10,
        dispersion_period: 10,
        window_size: 200,
    };

    let features = compute_all(&primary_values, &secondary_values, &config);

    assert!(features.contains_key("rolling_mean_5"));
    assert!(!features.contains_key("rolling_mean_7"));
    assert!(features.contains_key("rolling_ema_10"));
    assert!(!features.contains_key("rolling_ema_12"));
    assert!(features.contains_key("momentum_7"));
    assert!(!features.contains_key("momentum_14"));
    assert!(!features.contains_key("trend_convergence"));
    assert!(!features.contains_key("band_upper"));
}

#[test]
fn test_compute_all_empty_values() {
    let primary_values: Vec<f64> = vec![];
    let secondary_values: Vec<f64> = vec![];
    let config = IndicatorConfig::default();

    let features = compute_all(&primary_values, &secondary_values, &config);
    assert!(features.is_empty());
}

#[test]
fn test_features_serialization() {
    let primary_values: Vec<f64> = (1..=30).map(|x| x as f64 * 100.0).collect();
    let secondary_values: Vec<f64> = vec![1000.0; 30];
    let config = IndicatorConfig::default();

    let features = compute_all(&primary_values, &secondary_values, &config);
    let serialized = serde_json::to_string(&features).unwrap();
    let deserialized: std::collections::BTreeMap<String, f64> =
        serde_json::from_str(&serialized).unwrap();

    assert_eq!(features.len(), deserialized.len());
    assert_eq!(
        features.get("value").unwrap(),
        deserialized.get("value").unwrap()
    );
}
