use redis::{AsyncCommands, Client};
use std::sync::atomic::{AtomicU64, Ordering};
use tracing::error;

pub struct RedisCache {
    client: Client,
    ttl: u64,
    hits: AtomicU64,
    misses: AtomicU64,
}

impl RedisCache {
    pub fn new(url: &str, ttl: u64) -> anyhow::Result<Self> {
        Ok(Self {
            client: Client::open(url)?,
            ttl,
            hits: AtomicU64::new(0),
            misses: AtomicU64::new(0),
        })
    }

    pub async fn get(&self, key: &str) -> Option<String> {
        match self.client.get_multiplexed_async_connection().await {
            Ok(mut conn) => match conn.get::<_, Option<String>>(key).await {
                Ok(Some(val)) => {
                    self.hits.fetch_add(1, Ordering::Relaxed);
                    Some(val)
                }
                Ok(None) => {
                    self.misses.fetch_add(1, Ordering::Relaxed);
                    None
                }
                Err(e) => {
                    error!("Valkey get error: {}", e);
                    None
                }
            },
            Err(e) => {
                error!("Valkey connection error: {}", e);
                None
            }
        }
    }

    pub async fn set(&self, key: &str, value: &str) -> anyhow::Result<()> {
        let mut conn = self.client.get_multiplexed_async_connection().await?;
        let _: () = conn.set_ex(key, value, self.ttl).await?;
        Ok(())
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

    #[test]
    fn test_redis_cache_new() {
        let result = RedisCache::new("redis://localhost:6379", 300);
        assert!(result.is_ok());
    }

    #[test]
    fn test_redis_cache_invalid_url() {
        let result = RedisCache::new("invalid_url", 300);
        assert!(result.is_err());
    }

    #[test]
    fn test_redis_cache_stats_initial() {
        let cache = RedisCache::new("redis://localhost:6379", 300).unwrap();
        assert_eq!(cache.hits(), 0);
        assert_eq!(cache.misses(), 0);
    }

    #[test]
    fn test_redis_cache_ttl() {
        let cache = RedisCache::new("redis://localhost:6379", 7200).unwrap();
        assert_eq!(cache.ttl, 7200);
    }
}
