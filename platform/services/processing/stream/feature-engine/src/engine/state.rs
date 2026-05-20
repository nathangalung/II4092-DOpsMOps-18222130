use super::indicators::{compute_all, Features};
use super::Tick;
use crate::config::IndicatorConfig;
use std::collections::VecDeque;

pub struct SymbolState {
    prices: VecDeque<f64>,
    volumes: VecDeque<f64>,
    window_size: usize,
}

impl SymbolState {
    pub fn new(window_size: usize) -> Self {
        Self {
            prices: VecDeque::with_capacity(window_size),
            volumes: VecDeque::with_capacity(window_size),
            window_size,
        }
    }

    /// Update state from a generic tick.
    /// `primary_value_field` and `secondary_value_field` are configured per use-case.
    pub fn update(&mut self, tick: &Tick, primary_value_field: &str, secondary_value_field: &str) {
        if self.prices.len() >= self.window_size {
            self.prices.pop_front();
            self.volumes.pop_front();
        }

        let price = tick.get_f64(primary_value_field).unwrap_or(0.0);
        let volume = tick.get_f64(secondary_value_field).unwrap_or(0.0);

        self.prices.push_back(price);
        self.volumes.push_back(volume);
    }

    /// Compute features using the provided indicator configuration.
    /// Which indicators are computed is driven entirely by config.
    pub fn compute_features(&self, config: &IndicatorConfig) -> Features {
        let prices: Vec<f64> = self.prices.iter().copied().collect();
        let volumes: Vec<f64> = self.volumes.iter().copied().collect();

        compute_all(&prices, &volumes, config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    fn create_test_tick(symbol: &str, price: f64, volume: f64) -> Tick {
        let mut values = BTreeMap::new();
        values.insert("value".to_string(), serde_json::Value::from(price));
        values.insert("value_2".to_string(), serde_json::Value::from(volume));
        Tick {
            symbol: symbol.to_string(),
            timestamp: 1234567890,
            values,
        }
    }

    fn default_config() -> IndicatorConfig {
        IndicatorConfig {
            rolling_mean_periods: vec![7, 14],
            exp_avg_periods: vec![12, 26],
            momentum_period: 14,
            trend_convergence_enabled: false,
            deviation_bands_period: 20,
            deviation_bands_enabled: false,
            secondary_avg_period: 14,
            dispersion_period: 14,
            window_size: 200,
        }
    }

    #[test]
    fn test_symbol_state_new() {
        let state = SymbolState::new(200);
        assert_eq!(state.prices.len(), 0);
        assert_eq!(state.volumes.len(), 0);
    }

    #[test]
    fn test_symbol_state_update() {
        let mut state = SymbolState::new(200);
        let tick = create_test_tick("SAMPLE-001", 100.0, 100.0);

        state.update(&tick, "value", "value_2");

        assert_eq!(state.prices.len(), 1);
        assert_eq!(state.prices[0], 100.0);
        assert_eq!(state.volumes[0], 100.0);
    }

    #[test]
    fn test_symbol_state_window_overflow() {
        let mut state = SymbolState::new(200);

        for i in 0..250 {
            let tick = create_test_tick("SAMPLE-001", 100.0 + i as f64, 100.0);
            state.update(&tick, "value", "value_2");
        }

        assert_eq!(state.prices.len(), 200);
        assert_eq!(state.prices[0], 150.0);
    }

    #[test]
    fn test_compute_features_insufficient_data() {
        let state = SymbolState::new(200);
        let config = default_config();
        let features = state.compute_features(&config);
        assert!(features.is_empty());
    }

    #[test]
    fn test_compute_features_sufficient_data() {
        let mut state = SymbolState::new(200);
        let config = default_config();

        for i in 0..30 {
            let tick = create_test_tick("SAMPLE-001", 100.0 + i as f64, 100.0);
            state.update(&tick, "value", "value_2");
        }

        let features = state.compute_features(&config);
        assert!(features.contains_key("value"));
        assert!(features.contains_key("rolling_mean_7"));
        assert!(features.contains_key("rolling_mean_14"));
        assert!(*features.get("value").unwrap() > 0.0);
    }

    #[test]
    fn test_compute_features_custom_config() {
        let mut state = SymbolState::new(200);
        let config = IndicatorConfig {
            rolling_mean_periods: vec![5, 10],
            exp_avg_periods: vec![],
            momentum_period: 7,
            trend_convergence_enabled: false,
            deviation_bands_period: 10,
            deviation_bands_enabled: false,
            secondary_avg_period: 10,
            dispersion_period: 10,
            window_size: 200,
        };

        for i in 0..30 {
            let tick = create_test_tick("SAMPLE-001", 100.0 + i as f64, 100.0);
            state.update(&tick, "value", "value_2");
        }

        let features = state.compute_features(&config);
        assert!(features.contains_key("rolling_mean_5"));
        assert!(features.contains_key("rolling_mean_10"));
        assert!(!features.contains_key("rolling_mean_7"));
        assert!(!features.contains_key("trend_convergence"));
        assert!(!features.contains_key("band_upper"));
        assert!(features.contains_key("momentum_7"));
    }

    #[test]
    fn test_custom_field_names() {
        let mut state = SymbolState::new(200);

        // Test with non-default field names (e.g., temperature/humidity sensor data)
        let mut values = BTreeMap::new();
        values.insert("temperature".to_string(), serde_json::Value::from(25.5));
        values.insert("humidity".to_string(), serde_json::Value::from(60.0));
        let tick = Tick {
            symbol: "SENSOR-001".to_string(),
            timestamp: 1234567890,
            values,
        };

        state.update(&tick, "temperature", "humidity");

        assert_eq!(state.prices.len(), 1);
        assert_eq!(state.prices[0], 25.5);
        assert_eq!(state.volumes[0], 60.0);
    }
}
