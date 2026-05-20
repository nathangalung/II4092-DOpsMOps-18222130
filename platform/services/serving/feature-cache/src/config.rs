use config::{Config as CfgLoader, Environment, File};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub grpc_port: u16,
    pub health_port: u16,
    pub redis_url: String,
    pub sync_interval_ms: u64,
    #[serde(default = "default_symbols")]
    pub symbols: Vec<String>,
}

fn default_symbols() -> Vec<String> {
    std::env::var("FCACHE_SYMBOLS")
        .map(|s| s.split(',').map(|v| v.trim().to_string()).collect())
        .unwrap_or_else(|_| vec!["SYMBOL-A".to_string(), "SYMBOL-B".to_string()])
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        let cfg = CfgLoader::builder()
            .add_source(File::with_name("config").required(false))
            .add_source(Environment::with_prefix("FCACHE").separator("__"))
            .set_default("grpc_port", 50053)?
            .set_default("health_port", 8080)?
            .set_default("redis_url", "redis://localhost:6379")?
            .set_default("sync_interval_ms", 100)?
            .build()?;

        let mut loaded: Self = cfg.try_deserialize()?;
        loaded.redis_url =
            inject_redis_password(&loaded.redis_url, read_redis_password_env().as_deref());
        Ok(loaded)
    }
}

fn read_redis_password_env() -> Option<String> {
    std::env::var("VALKEY_PASSWORD").ok().filter(|p| !p.is_empty())
}

// See gateway/src/config.rs for rationale. Duplicated here to keep the two
// services independent of each other and avoid a shared-crate dependency
// for a ten-line helper. Password is URL-safe base64 by construction.
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
        assert_eq!(cfg.grpc_port, 50053);
        assert_eq!(cfg.health_port, 8080);
        assert_eq!(cfg.sync_interval_ms, 100);
    }

    #[test]
    fn test_config_symbols_from_env() {
        // `set_var`/`remove_var` are `unsafe` in the 2024 edition because
        // another thread may be reading the environment concurrently. Tests
        // in this module don't touch FCACHE_SYMBOLS elsewhere, so the pair
        // set/remove below is well-scoped.
        unsafe {
            std::env::set_var("FCACHE_SYMBOLS", "SYMBOL-A,SYMBOL-B");
        }
        let cfg = Config::load().unwrap();
        assert_eq!(cfg.symbols, vec!["SYMBOL-A", "SYMBOL-B"]);
        unsafe {
            std::env::remove_var("FCACHE_SYMBOLS");
        }
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
