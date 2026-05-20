use moka::future::Cache;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

pub struct MemoryCache {
    cache: Cache<String, String>,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl MemoryCache {
    pub fn new(max_capacity: u64, ttl_seconds: u64) -> Self {
        Self {
            cache: Cache::builder()
                .max_capacity(max_capacity)
                .time_to_live(Duration::from_secs(ttl_seconds))
                .build(),
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        }
    }

    pub async fn get(&self, key: &str) -> Option<String> {
        match self.cache.get(key).await {
            Some(val) => {
                self.hits.fetch_add(1, Ordering::Relaxed);
                Some(val)
            }
            None => {
                self.misses.fetch_add(1, Ordering::Relaxed);
                None
            }
        }
    }

    pub async fn set(&self, key: &str, value: &str) {
        self.cache.insert(key.to_string(), value.to_string()).await;
    }

    pub fn hits(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }

    pub fn misses(&self) -> u64 {
        self.misses.load(Ordering::Relaxed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_memory_cache_new() {
        let cache = MemoryCache::new(100, 60);
        assert_eq!(cache.hits(), 0);
        assert_eq!(cache.misses(), 0);
    }

    #[tokio::test]
    async fn test_memory_cache_set_get() {
        let cache = MemoryCache::new(100, 60);
        cache.set("key1", "value1").await;

        let result = cache.get("key1").await;
        assert_eq!(result, Some("value1".to_string()));
        assert_eq!(cache.hits(), 1);
        assert_eq!(cache.misses(), 0);
    }

    #[tokio::test]
    async fn test_memory_cache_miss() {
        let cache = MemoryCache::new(100, 60);

        let result = cache.get("nonexistent").await;
        assert_eq!(result, None);
        assert_eq!(cache.hits(), 0);
        assert_eq!(cache.misses(), 1);
    }

    #[tokio::test]
    async fn test_memory_cache_overwrite() {
        let cache = MemoryCache::new(100, 60);
        cache.set("key1", "value1").await;
        cache.set("key1", "value2").await;

        let result = cache.get("key1").await;
        assert_eq!(result, Some("value2".to_string()));
    }

    #[tokio::test]
    async fn test_memory_cache_multiple_keys() {
        let cache = MemoryCache::new(100, 60);
        cache.set("key1", "value1").await;
        cache.set("key2", "value2").await;
        cache.set("key3", "value3").await;

        assert_eq!(cache.get("key1").await, Some("value1".to_string()));
        assert_eq!(cache.get("key2").await, Some("value2".to_string()));
        assert_eq!(cache.get("key3").await, Some("value3".to_string()));
        assert_eq!(cache.hits(), 3);
    }

    #[tokio::test]
    async fn test_memory_cache_stats() {
        let cache = MemoryCache::new(100, 60);
        cache.set("key1", "value1").await;

        cache.get("key1").await;
        cache.get("key1").await;
        cache.get("missing").await;

        assert_eq!(cache.hits(), 2);
        assert_eq!(cache.misses(), 1);
    }
}
