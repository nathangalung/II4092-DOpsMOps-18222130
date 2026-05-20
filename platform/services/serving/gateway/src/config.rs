use config::{Config as CfgLoader, Environment, File};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub http_port: u16,
    pub ws_port: u16,
    pub health_port: u16,
    pub cache: CacheConfig,
    pub inference: InferenceConfig,
}

#[derive(Debug, Deserialize)]
pub struct CacheConfig {
    pub memory_max_capacity: u64,
    pub memory_ttl_seconds: u64,
    pub redis_url: String,
    pub redis_ttl_seconds: u64,
}

#[derive(Debug, Deserialize)]
pub struct InferenceConfig {
    pub endpoint: String,
    pub timeout_ms: u64,
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        let cfg = CfgLoader::builder()
            .add_source(File::with_name("config").required(false))
            .add_source(Environment::with_prefix("GATEWAY"))
            .set_default("http_port", 8080)?
            .set_default("ws_port", 8081)?
            .set_default("health_port", 8082)?
            .set_default("cache.memory_max_capacity", 10000)?
            .set_default("cache.memory_ttl_seconds", 60)?
            .set_default("cache.redis_url", "redis://localhost:6379")?
            .set_default("cache.redis_ttl_seconds", 300)?
            .set_default("inference.endpoint", "http://localhost:50052")?
            .set_default("inference.timeout_ms", 5000)?
            .build()?;

        let mut loaded: Self = cfg.try_deserialize()?;
        loaded.cache.redis_url =
            inject_redis_password(&loaded.cache.redis_url, read_redis_password_env().as_deref());
        Ok(loaded)
    }
}

fn read_redis_password_env() -> Option<String> {
    std::env::var("VALKEY_PASSWORD").ok().filter(|p| !p.is_empty())
}

// Merge `VALKEY_PASSWORD` (from the pipeline-secrets Secret) into the
// connection URL. redis-rs only accepts credentials via the URL userinfo,
// and every call site already reads `redis_url` (struct field kept on the
// `redis_*` prefix because the wire protocol is RESP — the Rust crate is
// `redis-rs` speaking to a Valkey server). The password is seeded in
// OpenBao as URL-safe base64 (no `+` `/` `=`), so a raw embed into the
// userinfo is RFC-3986-compliant without pulling in a percent-encoder.
// Left untouched when the password is absent (dev / no-auth) or when the URL
// already carries userinfo (explicit override via config file or env).
pub(crate) fn inject_redis_password(url: &str, password: Option<&str>) -> String {
    let Some(password) = password.filter(|p| !p.is_empty()) else {
        return url.to_string();
    };
    let Some((scheme, rest)) = url.split_once("://") else {
        return url.to_string();
    };
    if rest.contains('@') {
        return url.to_string();
    }
    format!("{scheme}://:{password}@{rest}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        let cfg = Config::load().unwrap();
        assert_eq!(cfg.http_port, 8080);
        assert_eq!(cfg.ws_port, 8081);
        assert_eq!(cfg.health_port, 8082);
    }

    #[test]
    fn test_cache_config() {
        let cache = CacheConfig {
            memory_max_capacity: 10000,
            memory_ttl_seconds: 60,
            redis_url: "redis://localhost:6379".to_string(),
            redis_ttl_seconds: 300,
        };

        assert_eq!(cache.memory_max_capacity, 10000);
        assert_eq!(cache.memory_ttl_seconds, 60);
        assert_eq!(cache.redis_url, "redis://localhost:6379");
        assert_eq!(cache.redis_ttl_seconds, 300);
    }

    #[test]
    fn test_inference_config() {
        let inference = InferenceConfig {
            endpoint: "http://model-server:50052".to_string(),
            timeout_ms: 5000,
        };

        assert_eq!(inference.endpoint, "http://model-server:50052");
        assert_eq!(inference.timeout_ms, 5000);
    }

    #[test]
    fn test_config_debug_format() {
        let cfg = Config::load().unwrap();
        let debug_str = format!("{:?}", cfg);
        assert!(debug_str.contains("http_port"));
        assert!(debug_str.contains("cache"));
    }

    #[test]
    fn inject_redis_password_none_leaves_url_untouched() {
        assert_eq!(
            inject_redis_password("redis://localhost:6379", None),
            "redis://localhost:6379"
        );
    }

    #[test]
    fn inject_redis_password_empty_leaves_url_untouched() {
        assert_eq!(
            inject_redis_password("redis://localhost:6379", Some("")),
            "redis://localhost:6379"
        );
    }

    #[test]
    fn inject_redis_password_with_existing_userinfo_leaves_url_untouched() {
        assert_eq!(
            inject_redis_password("redis://user:other@localhost:6379", Some("secret")),
            "redis://user:other@localhost:6379"
        );
    }

    #[test]
    fn inject_redis_password_embeds_password_into_userinfo() {
        assert_eq!(
            inject_redis_password("redis://localhost:6379", Some("s3cret")),
            "redis://:s3cret@localhost:6379"
        );
    }
}
