//! Configuration for WebSocket collector

use anyhow::Result;
use rdkafka::ClientConfig;
use serde::Deserialize;

#[derive(Debug, Deserialize, Clone)]
pub struct Config {
    pub kafka: KafkaConfig,
    pub sources: Vec<SourceConfig>,
    pub health_port: u16,
}

#[derive(Debug, Default, Deserialize, Clone)]
pub struct KafkaConfig {
    pub brokers: String,
    pub topic: String,
    pub batch_size: usize,
    pub flush_interval_ms: u64,
    /// Optional SASL/SSL — set by use-cases needing auth.
    /// Platform default (None) keeps PLAINTEXT to stay domain-agnostic.
    #[serde(default)]
    pub security_protocol: Option<String>,
    #[serde(default)]
    pub sasl_mechanism: Option<String>,
    #[serde(default)]
    pub sasl_username: Option<String>,
    #[serde(default)]
    pub sasl_password: Option<String>,
    #[serde(default)]
    pub ssl_ca_location: Option<String>,
}

impl KafkaConfig {
    /// Apply SASL/SSL settings to an rdkafka ClientConfig.
    /// No-op when security_protocol is unset.
    pub fn apply_security(&self, cfg: &mut ClientConfig) {
        let Some(proto) = self.security_protocol.as_deref() else {
            return;
        };
        cfg.set("security.protocol", proto);
        if let Some(m) = &self.sasl_mechanism {
            cfg.set("sasl.mechanisms", m);
        }
        if let Some(u) = &self.sasl_username {
            cfg.set("sasl.username", u);
        }
        if let Some(p) = &self.sasl_password {
            cfg.set("sasl.password", p);
        }
        if let Some(ca) = &self.ssl_ca_location {
            cfg.set("ssl.ca.location", ca);
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct SourceConfig {
    pub enabled: bool,
    pub name: String,
    pub ws_url: String,
    pub subscribe_msg: Option<String>,
    pub symbols: Vec<String>,
}

impl Config {
    /// Load from environment/file
    pub fn load() -> Result<Self> {
        let cfg = config::Config::builder()
            .add_source(config::Environment::with_prefix("COLLECTOR"))
            .set_default("health_port", 8080)?
            .set_default(
                "kafka.brokers",
                "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092",
            )?
            .set_default("kafka.topic", "ingested_data")?
            .set_default("kafka.batch_size", 500)?
            .set_default("kafka.flush_interval_ms", 100)?
            .set_default::<&str, Vec<String>>("sources", vec![])?
            .build()?;

        let mut cfg: Config = cfg.try_deserialize()?;

        // Override from env vars (no prefix)
        if let Ok(v) = std::env::var("KAFKA_BROKERS") {
            cfg.kafka.brokers = v;
        }
        if let Ok(v) = std::env::var("KAFKA_TOPIC") {
            cfg.kafka.topic = v;
        }
        // SASL/SSL — use-case sets these via ConfigMap; platform default
        // leaves them None and the producer runs PLAINTEXT.
        if let Ok(v) = std::env::var("KAFKA_SECURITY_PROTOCOL") {
            cfg.kafka.security_protocol = Some(v);
        }
        if let Ok(v) = std::env::var("KAFKA_SASL_MECHANISM") {
            cfg.kafka.sasl_mechanism = Some(v);
        }
        if let Ok(v) = std::env::var("KAFKA_SASL_USERNAME") {
            cfg.kafka.sasl_username = Some(v);
        }
        if let Ok(v) = std::env::var("KAFKA_SASL_PASSWORD") {
            cfg.kafka.sasl_password = Some(v);
        }
        if let Ok(v) = std::env::var("KAFKA_SSL_CA_LOCATION") {
            cfg.kafka.ssl_ca_location = Some(v);
        }
        if let Ok(v) = std::env::var("SERVER_PORT")
            && let Ok(p) = v.parse()
        {
            cfg.health_port = p;
        }

        // Build sources from WS_* env vars if no sources configured from file
        if cfg.sources.is_empty()
            && let Some(source) = build_source_from_env()
        {
            cfg.sources.push(source);
        }

        Ok(cfg)
    }
}

/// Build a WebSocket source config from WS_* environment variables.
/// Supports WS_NAME, WS_URL, WS_SUBSCRIBE_MSG, WS_SYMBOLS, WS_ENABLED.
fn build_source_from_env() -> Option<SourceConfig> {
    let name = std::env::var("WS_NAME").ok()?;
    let ws_url = std::env::var("WS_URL").ok()?;

    let enabled = std::env::var("WS_ENABLED")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(true);

    let subscribe_msg = std::env::var("WS_SUBSCRIBE_MSG").ok();

    let symbols = std::env::var("WS_SYMBOLS")
        .ok()
        .map(|v| v.split(',').map(|s| s.trim().to_string()).collect())
        .unwrap_or_default();

    Some(SourceConfig {
        enabled,
        name,
        ws_url,
        subscribe_msg,
        symbols,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_config_clone() {
        let kafka = KafkaConfig {
            brokers: "localhost:9092".to_string(),
            topic: "test-topic".to_string(),
            batch_size: 100,
            flush_interval_ms: 50,
            ..Default::default()
        };
        let cloned = kafka.clone();
        assert_eq!(kafka.brokers, cloned.brokers);
        assert_eq!(kafka.topic, cloned.topic);
        assert_eq!(kafka.batch_size, cloned.batch_size);
    }

    #[test]
    fn test_source_config_enabled() {
        let source = SourceConfig {
            enabled: true,
            name: "test-source".to_string(),
            ws_url: "wss://example.com".to_string(),
            subscribe_msg: Some(r#"{"type":"subscribe"}"#.to_string()),
            symbols: vec!["SYM1".to_string()],
        };
        assert!(source.enabled);
        assert_eq!(source.symbols.len(), 1);
        assert_eq!(source.name, "test-source");
    }

    #[test]
    fn test_source_config_disabled() {
        let source = SourceConfig {
            enabled: false,
            name: "test-source".to_string(),
            ws_url: "wss://example.com".to_string(),
            subscribe_msg: None,
            symbols: vec![],
        };
        assert!(!source.enabled);
        assert!(source.symbols.is_empty());
    }

    #[test]
    fn test_config_debug_format() {
        let kafka = KafkaConfig {
            brokers: "test:9092".to_string(),
            topic: "test".to_string(),
            batch_size: 10,
            flush_interval_ms: 5,
            ..Default::default()
        };
        let debug_str = format!("{:?}", kafka);
        assert!(debug_str.contains("test:9092"));
        assert!(debug_str.contains("test"));
    }

    #[test]
    fn test_source_config_with_subscribe_msg() {
        let source = SourceConfig {
            enabled: true,
            name: "test-ws".to_string(),
            ws_url: "wss://stream.example.com".to_string(),
            subscribe_msg: Some(r#"{"action":"subscribe","channels":["ticker"]}"#.to_string()),
            symbols: vec!["SYM1".to_string(), "SYM2".to_string()],
        };
        assert!(source.subscribe_msg.is_some());
        assert_eq!(source.symbols.len(), 2);
    }

    #[test]
    fn test_source_config_without_subscribe_msg() {
        let source = SourceConfig {
            enabled: true,
            name: "test-ws".to_string(),
            ws_url: "wss://stream.example.com/ws".to_string(),
            subscribe_msg: None,
            symbols: vec!["SYM1".to_string()],
        };
        assert!(source.subscribe_msg.is_none());
    }
}
