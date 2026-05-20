pub mod memory;
pub mod redis_cache;

use serde::Serialize;
use tracing::debug;

use crate::config::CacheConfig;
use memory::MemoryCache;
use redis_cache::RedisCache;

pub struct CacheLayer {
    memory: MemoryCache,
    redis: RedisCache,
}

#[derive(Serialize)]
pub struct CacheStats {
    pub memory_hits: u64,
    pub memory_misses: u64,
    pub redis_hits: u64,
    pub redis_misses: u64,
}

impl CacheLayer {
    pub fn new(cfg: &CacheConfig) -> anyhow::Result<Self> {
        Ok(Self {
            memory: MemoryCache::new(cfg.memory_max_capacity, cfg.memory_ttl_seconds),
            redis: RedisCache::new(&cfg.redis_url, cfg.redis_ttl_seconds)?,
        })
    }

    pub async fn get(&self, key: &str) -> Option<String> {
        if let Some(val) = self.memory.get(key).await {
            debug!("Memory cache hit: {}", key);
            return Some(val);
        }

        if let Some(val) = self.redis.get(key).await {
            debug!("Valkey cache hit (RESP): {}", key);
            self.memory.set(key, &val).await;
            return Some(val);
        }

        None
    }

    pub async fn set(&self, key: &str, value: &str) -> anyhow::Result<()> {
        self.memory.set(key, value).await;
        self.redis.set(key, value).await
    }

    pub fn stats(&self) -> CacheStats {
        CacheStats {
            memory_hits: self.memory.hits(),
            memory_misses: self.memory.misses(),
            redis_hits: self.redis.hits(),
            redis_misses: self.redis.misses(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cache_stats_creation() {
        let stats = CacheStats {
            memory_hits: 10,
            memory_misses: 5,
            redis_hits: 3,
            redis_misses: 2,
        };

        assert_eq!(stats.memory_hits, 10);
        assert_eq!(stats.memory_misses, 5);
        assert_eq!(stats.redis_hits, 3);
        assert_eq!(stats.redis_misses, 2);
    }

    #[test]
    fn test_cache_stats_serialization() {
        let stats = CacheStats {
            memory_hits: 100,
            memory_misses: 20,
            redis_hits: 50,
            redis_misses: 10,
        };

        let json = serde_json::to_string(&stats).unwrap();
        assert!(json.contains("\"memory_hits\":100"));
        assert!(json.contains("\"redis_hits\":50"));
    }

    #[test]
    fn test_cache_layer_new() {
        let config = CacheConfig {
            memory_max_capacity: 1000,
            memory_ttl_seconds: 60,
            redis_url: "redis://localhost:6379".to_string(),
            redis_ttl_seconds: 300,
        };

        let result = CacheLayer::new(&config);
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_cache_layer_stats() {
        let config = CacheConfig {
            memory_max_capacity: 1000,
            memory_ttl_seconds: 60,
            redis_url: "redis://localhost:6379".to_string(),
            redis_ttl_seconds: 300,
        };

        let cache = CacheLayer::new(&config).unwrap();
        let stats = cache.stats();

        assert_eq!(stats.memory_hits, 0);
        assert_eq!(stats.memory_misses, 0);
        assert_eq!(stats.redis_hits, 0);
        assert_eq!(stats.redis_misses, 0);
    }
}
