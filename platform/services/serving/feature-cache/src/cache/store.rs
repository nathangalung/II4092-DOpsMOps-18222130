use dashmap::DashMap;
use redis::AsyncCommands;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;
use tracing::{debug, error, info};

use crate::config::Config;

/// Dynamic feature map — keys are feature names (configured per use-case),
/// values are computed f64 values. No hardcoded field names.
pub type Features = BTreeMap<String, f64>;

#[allow(dead_code)]
pub struct FeatureStore {
    cache: DashMap<String, Features>,
    redis_client: redis::Client,
    symbols: Vec<String>,
    sync_interval: Duration,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl FeatureStore {
    pub fn new(cfg: &Config) -> anyhow::Result<Self> {
        let redis_client = redis::Client::open(cfg.redis_url.as_str())?;

        Ok(Self {
            cache: DashMap::new(),
            redis_client,
            symbols: cfg.symbols.clone(),
            sync_interval: Duration::from_millis(cfg.sync_interval_ms),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        })
    }

    #[allow(dead_code)]
    pub fn get(&self, symbol: &str) -> Option<Features> {
        match self.cache.get(symbol) {
            Some(entry) => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(entry.clone())
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    #[allow(dead_code)]
    pub fn set(&self, symbol: &str, features: Features) {
        self.cache.insert(symbol.to_string(), features);
    }

    pub async fn sync_from_valkey(&self) -> anyhow::Result<()> {
        info!("Starting Valkey sync loop (RESP)");

        loop {
            for symbol in &self.symbols {
                if let Err(e) = self.sync_symbol(symbol).await {
                    error!("Sync error for {}: {}", symbol, e);
                }
            }

            tokio::time::sleep(self.sync_interval).await;
        }
    }

    async fn sync_symbol(&self, symbol: &str) -> anyhow::Result<()> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;
        let key = format!("features:{}", symbol);

        let value: Option<String> = conn.get(&key).await?;

        if let Some(json) = value
            && let Ok(features) = serde_json::from_str::<Features>(&json)
        {
            debug!("Synced features for {}", symbol);
            self.cache.insert(symbol.to_string(), features);
        }

        Ok(())
    }

    #[allow(dead_code)]
    pub fn stats(&self) -> (u64, u64, usize) {
        (
            self.hits.load(Ordering::Relaxed),
            self.misses.load(Ordering::Relaxed),
            self.cache.len(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_features() -> Features {
        let mut f = Features::new();
        f.insert("value".to_string(), 100.0);
        f.insert("indicator_a".to_string(), 98.0);
        f.insert("indicator_b".to_string(), 55.0);
        f.insert("dispersion".to_string(), 500.0);
        f
    }

    #[test]
    fn test_features_default() {
        let features = Features::new();
        assert!(features.is_empty());
    }

    #[test]
    fn test_features_serialization() {
        let features = create_test_features();
        let json = serde_json::to_string(&features).unwrap();
        assert!(json.contains("100"));
        assert!(json.contains("indicator_b"));
    }

    #[test]
    fn test_features_deserialization() {
        let json = r#"{
            "value": 200.0,
            "indicator_a": 198.0,
            "indicator_b": 65.0,
            "dispersion": 8.0
        }"#;

        let features: Features = serde_json::from_str(json).unwrap();
        assert_eq!(*features.get("value").unwrap(), 200.0);
        assert_eq!(*features.get("indicator_b").unwrap(), 65.0);
    }

    #[test]
    fn test_feature_store_get_miss() {
        let config = Config {
            grpc_port: 50053,
            health_port: 8080,
            redis_url: "redis://localhost:6379".to_string(),
            sync_interval_ms: 100,
            symbols: vec!["SYMBOL-A".to_string()],
        };

        let store = FeatureStore::new(&config).unwrap();
        let result = store.get("SYMBOL-A");
        assert!(result.is_none());

        let (hits, misses, _) = store.stats();
        assert_eq!(hits, 0);
        assert_eq!(misses, 1);
    }

    #[test]
    fn test_feature_store_set_get() {
        let config = Config {
            grpc_port: 50053,
            health_port: 8080,
            redis_url: "redis://localhost:6379".to_string(),
            sync_interval_ms: 100,
            symbols: vec!["SYMBOL-A".to_string()],
        };

        let store = FeatureStore::new(&config).unwrap();
        let features = create_test_features();

        store.set("SYMBOL-A", features.clone());
        let result = store.get("SYMBOL-A");

        assert!(result.is_some());
        let retrieved = result.unwrap();
        assert_eq!(*retrieved.get("value").unwrap(), 100.0);

        let (hits, _, _) = store.stats();
        assert_eq!(hits, 1);
    }

    #[test]
    fn test_feature_store_multiple_symbols() {
        let config = Config {
            grpc_port: 50053,
            health_port: 8080,
            redis_url: "redis://localhost:6379".to_string(),
            sync_interval_ms: 100,
            symbols: vec!["SYMBOL-A".to_string(), "SYMBOL-B".to_string()],
        };

        let store = FeatureStore::new(&config).unwrap();

        let features_a = create_test_features();
        let mut features_b = create_test_features();
        features_b.insert("value".to_string(), 3000.0);

        store.set("SYMBOL-A", features_a);
        store.set("SYMBOL-B", features_b);

        let result_a = store.get("SYMBOL-A").unwrap();
        let result_b = store.get("SYMBOL-B").unwrap();

        assert_eq!(*result_a.get("value").unwrap(), 100.0);
        assert_eq!(*result_b.get("value").unwrap(), 3000.0);
    }

    #[test]
    fn test_feature_store_stats() {
        let config = Config {
            grpc_port: 50053,
            health_port: 8080,
            redis_url: "redis://localhost:6379".to_string(),
            sync_interval_ms: 100,
            symbols: vec!["SYMBOL-A".to_string()],
        };

        let store = FeatureStore::new(&config).unwrap();
        let features = create_test_features();

        store.set("SYMBOL-A", features);
        store.get("SYMBOL-A");
        store.get("SYMBOL-A");
        store.get("SYMBOL-B");

        let (hits, misses, size) = store.stats();
        assert_eq!(hits, 2);
        assert_eq!(misses, 1);
        assert_eq!(size, 1);
    }
}
