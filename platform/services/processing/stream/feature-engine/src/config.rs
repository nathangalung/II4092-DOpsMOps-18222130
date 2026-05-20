use config::{Config as CfgLoader, Environment, File};
use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub kafka: KafkaConfig,
    pub redis: RedisConfig,
    pub grpc_port: u16,
    pub health_port: u16,
    pub symbols: Vec<String>,
    #[serde(default)]
    pub indicators: IndicatorConfig,
}

#[derive(Debug, Deserialize)]
pub struct KafkaConfig {
    pub brokers: String,
    pub input_topic: String,
    pub output_topic: String,
    pub group_id: String,
}

#[derive(Debug, Deserialize)]
pub struct RedisConfig {
    pub url: String,
    pub ttl_seconds: u64,
}

/// Configurable indicator computation.
/// Use-cases override these via config file or environment variables.
/// All periods and flags are configurable — no hardcoded domain logic.
#[derive(Debug, Deserialize)]
pub struct IndicatorConfig {
    pub rolling_mean_periods: Vec<usize>,
    pub exp_avg_periods: Vec<usize>,
    pub momentum_period: usize,
    pub trend_convergence_enabled: bool,
    pub deviation_bands_period: usize,
    pub deviation_bands_enabled: bool,
    pub secondary_avg_period: usize,
    pub dispersion_period: usize,
    pub window_size: usize,
}

impl Default for IndicatorConfig {
    fn default() -> Self {
        Self {
            rolling_mean_periods: vec![],
            exp_avg_periods: vec![],
            momentum_period: 14,
            trend_convergence_enabled: false,
            deviation_bands_period: 20,
            deviation_bands_enabled: false,
            secondary_avg_period: 20,
            dispersion_period: 14,
            window_size: 200,
        }
    }
}

impl Config {
    pub fn load() -> anyhow::Result<Self> {
        let cfg = CfgLoader::builder()
            .add_source(File::with_name("config").required(false))
            .add_source(Environment::with_prefix("FEATURE").separator("__"))
            .set_default("grpc_port", 50051)?
            .set_default("health_port", 8080)?
            .set_default("kafka.brokers", "localhost:9092")?
            .set_default("kafka.input_topic", "validated")?
            .set_default("kafka.output_topic", "features")?
            .set_default("kafka.group_id", "feature-engine")?
            .set_default("redis.url", "redis://localhost:6379")?
            .set_default("redis.ttl_seconds", 3600)?
            .set_default("symbols", vec!["SAMPLE-001", "SAMPLE-002"])?
            .build()?;

        let mut loaded: Self = cfg.try_deserialize()?;
        loaded.redis.url =
            inject_redis_password(&loaded.redis.url, read_redis_password_env().as_deref());
        Ok(loaded)
    }
}

fn read_redis_password_env() -> Option<String> {
    std::env::var("VALKEY_PASSWORD").ok().filter(|p| !p.is_empty())
}

// See gateway/src/config.rs for rationale. Duplicated here to keep the two
// services independent and avoid a shared-crate dependency for a ten-line
// helper. Password is URL-safe base64 by construction, so no percent-
// encoding is required.
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
        assert_eq!(cfg.grpc_port, 50051);
        assert_eq!(cfg.health_port, 8080);
        assert_eq!(cfg.kafka.brokers, "localhost:9092");
        assert_eq!(cfg.kafka.input_topic, "validated");
        assert_eq!(cfg.kafka.output_topic, "features");
        assert_eq!(cfg.kafka.group_id, "feature-engine");
        assert_eq!(cfg.redis.url, "redis://localhost:6379");
        assert_eq!(cfg.redis.ttl_seconds, 3600);
    }

    #[test]
    fn test_indicator_defaults() {
        let ind = IndicatorConfig::default();
        let empty: Vec<usize> = vec![];
        assert_eq!(ind.rolling_mean_periods, empty);
        assert_eq!(ind.exp_avg_periods, empty);
        assert_eq!(ind.momentum_period, 14);
        assert!(!ind.trend_convergence_enabled);
        assert!(!ind.deviation_bands_enabled);
        assert_eq!(ind.window_size, 200);
    }

    #[test]
    fn test_kafka_config() {
        let kafka = KafkaConfig {
            brokers: "broker1:9092,broker2:9092".to_string(),
            input_topic: "input".to_string(),
            output_topic: "output".to_string(),
            group_id: "test-group".to_string(),
        };

        assert_eq!(kafka.brokers, "broker1:9092,broker2:9092");
        assert_eq!(kafka.input_topic, "input");
        assert_eq!(kafka.output_topic, "output");
        assert_eq!(kafka.group_id, "test-group");
    }

    #[test]
    fn test_redis_config() {
        let redis = RedisConfig {
            url: "redis://redis:6379".to_string(),
            ttl_seconds: 7200,
        };

        assert_eq!(redis.url, "redis://redis:6379");
        assert_eq!(redis.ttl_seconds, 7200);
    }

    #[test]
    fn test_config_symbols() {
        let cfg = Config::load().unwrap();
        assert!(!cfg.symbols.is_empty());
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
