use std::collections::BTreeMap;

use crate::config::IndicatorConfig;

/// Dynamic feature map — keys are indicator names (e.g., "rolling_mean_7"),
/// values are computed f64 values. Use-cases control which indicators appear
/// by configuring `IndicatorConfig` in their config file.
pub type Features = BTreeMap<String, f64>;

/// Compute all configured indicators from primary/secondary value time series.
/// Which indicators are computed and with what periods is driven by config,
/// not hardcoded. These are generic time series operations (windowed averages,
/// momentum, dispersion) applicable to any numeric data — not domain-specific.
/// Use-cases provide their own indicator configuration via config file.
pub fn compute_all(
    primary_values: &[f64],
    secondary_values: &[f64],
    config: &IndicatorConfig,
) -> Features {
    let mut features = Features::new();

    if primary_values.is_empty() {
        return features;
    }

    features.insert("value".to_string(), *primary_values.last().unwrap_or(&0.0));

    // Rolling mean — configurable periods
    for &period in &config.rolling_mean_periods {
        features.insert(
            format!("rolling_mean_{}", period),
            compute_rolling_mean(primary_values, period),
        );
    }

    // Exponential rolling mean — configurable periods
    for &period in &config.exp_avg_periods {
        features.insert(
            format!("rolling_ema_{}", period),
            compute_exp_avg(primary_values, period),
        );
    }

    // Momentum oscillator — configurable period
    features.insert(
        format!("momentum_{}", config.momentum_period),
        compute_momentum(primary_values, config.momentum_period),
    );

    // Trend convergence — optional
    if config.trend_convergence_enabled {
        let (convergence, signal, hist) = compute_trend_convergence(primary_values);
        features.insert("trend_convergence".to_string(), convergence);
        features.insert("trend_signal".to_string(), signal);
        features.insert("trend_hist".to_string(), hist);
    }

    // Deviation bands — optional, configurable period
    if config.deviation_bands_enabled {
        let (upper, middle, lower) =
            compute_deviation_bands(primary_values, config.deviation_bands_period);
        features.insert("band_upper".to_string(), upper);
        features.insert("band_middle".to_string(), middle);
        features.insert("band_lower".to_string(), lower);
    }

    // Secondary value rolling mean
    if !secondary_values.is_empty() {
        features.insert(
            "secondary_avg".to_string(),
            compute_rolling_mean(secondary_values, config.secondary_avg_period),
        );
    }

    // Value change and dispersion
    features.insert(
        "value_change".to_string(),
        compute_value_change(primary_values),
    );
    features.insert(
        "dispersion".to_string(),
        compute_dispersion(primary_values, config.dispersion_period),
    );

    features
}

pub fn compute_rolling_mean(values: &[f64], period: usize) -> f64 {
    if values.len() < period {
        return 0.0;
    }
    let slice = &values[values.len() - period..];
    slice.iter().sum::<f64>() / period as f64
}

pub fn compute_exp_avg(values: &[f64], period: usize) -> f64 {
    if values.is_empty() {
        return 0.0;
    }

    let k = 2.0 / (period as f64 + 1.0);
    let mut result = values[0];

    for val in values.iter().skip(1) {
        result = val * k + result * (1.0 - k);
    }

    result
}

pub fn compute_momentum(values: &[f64], period: usize) -> f64 {
    if values.len() < period + 1 {
        return 50.0;
    }

    let mut gains = 0.0;
    let mut losses = 0.0;

    for i in (values.len() - period)..values.len() {
        let change = values[i] - values[i - 1];
        if change > 0.0 {
            gains += change;
        } else {
            losses -= change;
        }
    }

    let avg_gain = gains / period as f64;
    let avg_loss = losses / period as f64;

    if avg_loss == 0.0 {
        return 100.0;
    }

    let rs = avg_gain / avg_loss;
    100.0 - (100.0 / (1.0 + rs))
}

pub fn compute_trend_convergence(values: &[f64]) -> (f64, f64, f64) {
    if values.len() < 26 {
        return (0.0, 0.0, 0.0);
    }

    let fast = compute_exp_avg(values, 12);
    let slow = compute_exp_avg(values, 26);
    let convergence = fast - slow;

    let signal = convergence * (2.0 / 10.0);
    let hist = convergence - signal;

    (convergence, signal, hist)
}

pub fn compute_deviation_bands(values: &[f64], period: usize) -> (f64, f64, f64) {
    if values.len() < period {
        return (0.0, 0.0, 0.0);
    }

    let slice = &values[values.len() - period..];
    let mean = slice.iter().sum::<f64>() / period as f64;

    let variance = slice.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / period as f64;
    let std_dev = variance.sqrt();

    let upper = mean + 2.0 * std_dev;
    let lower = mean - 2.0 * std_dev;

    (upper, mean, lower)
}

pub fn compute_value_change(values: &[f64]) -> f64 {
    if values.len() < 2 {
        return 0.0;
    }
    let current = values[values.len() - 1];
    let previous = values[values.len() - 2];
    if previous == 0.0 {
        0.0
    } else {
        (current - previous) / previous * 100.0
    }
}

pub fn compute_dispersion(values: &[f64], period: usize) -> f64 {
    if values.len() < period {
        return 0.0;
    }

    let slice = &values[values.len() - period..];
    let mean = slice.iter().sum::<f64>() / period as f64;
    let variance = slice.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / period as f64;
    variance.sqrt()
}
