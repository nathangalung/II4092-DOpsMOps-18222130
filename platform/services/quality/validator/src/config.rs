//! Configuration — generic, domain-agnostic.
//! All validation rules (schema, bounds, columns) are configurable via env vars.

use anyhow::Result;
use rdkafka::ClientConfig;
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub kafka: KafkaConfig,
    pub schema: String,
    pub bounds: BoundsConfig,
    pub bloom_size: usize,
    pub bloom_fp_rate: f64,
    pub health_port: u16,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct KafkaConfig {
    pub brokers: String,
    pub input_topic: String,
    pub output_topic: String,
    /// Optional SASL/SSL — set to "SASL_SSL" by use-cases needing auth.
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
    /// Apply security settings to an rdkafka ClientConfig builder.
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

#[derive(Debug, Clone, Deserialize)]
pub struct BoundsConfig {
    /// Columns to range-check (comma-separated). Read from RANGE_CHECK_COLUMNS env var.
    pub range_check_columns: String,
    pub range_min: f64,
    pub range_max: f64,
    /// Columns that must be non-negative (comma-separated). Read from NONNEG_COLUMNS env var.
    pub nonneg_columns: String,
}

impl Config {
    pub fn load() -> Result<Self> {
        // Generic default schema — only requires symbol + timestamp.
        // Use-cases override via VALIDATOR__SCHEMA env var with their full schema.
        let schema = r#"{
            "type": "object",
            "required": ["symbol", "timestamp"],
            "properties": {
                "symbol": {"type": "string"},
                "timestamp": {"type": "string"}
            }
        }"#;

        let cfg = config::Config::builder()
            .set_default("health_port", 8082)?
            .set_default("bloom_size", 1_000_000)?
            .set_default("bloom_fp_rate", 0.001)?
            .set_default(
                "kafka.brokers",
                "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092",
            )?
            .set_default("kafka.input_topic", "raw")?
            .set_default("kafka.output_topic", "validated")?
            .set_default("bounds.range_check_columns", "")?
            .set_default("bounds.range_min", 0.0)?
            .set_default("bounds.range_max", 1_000_000.0)?
            .set_default("bounds.nonneg_columns", "")?
            .set_default("schema", schema)?
            .add_source(config::Environment::with_prefix("VALIDATOR"))
            .build()?;

        let mut cfg: Config = cfg.try_deserialize()?;

        // Override from K8s ConfigMap env vars (no prefix).
        // The config crate with_prefix("VALIDATOR") without .separator() does NOT
        // support nesting, so we read flat env vars for all configurable fields.
        if let Ok(v) = std::env::var("KAFKA_BROKERS") {
            cfg.kafka.brokers = v;
        }
        // VALIDATOR_INPUT_TOPICS (CSV) is the canonical fan-in input env —
        // separating consumer semantics from the producer-output KAFKA_TOPIC
        // that collector Deployments use. Falls back to KAFKA_TOPIC for
        // back-compat with stand-alone validator deployments that haven't
        // adopted the dedicated env yet.
        if let Ok(v) = std::env::var("VALIDATOR_INPUT_TOPICS") {
            cfg.kafka.input_topic = v;
        } else if let Ok(v) = std::env::var("KAFKA_TOPIC") {
            cfg.kafka.input_topic = v;
        }
        if let Ok(v) = std::env::var("KAFKA_OUTPUT_TOPIC") {
            cfg.kafka.output_topic = v;
        }
        // SASL/SSL security config — only populated when the deploying
        // use-case sets these env vars. Platform default leaves them None
        // and the rdkafka client runs PLAINTEXT.
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
        if let Ok(v) = std::env::var("VALIDATOR_SCHEMA") {
            cfg.schema = v;
        }
        if let Ok(v) = std::env::var("SERVER_PORT")
            && let Ok(p) = v.parse()
        {
            cfg.health_port = p;
        }
        // Read bounds config from pipeline-config env vars
        if let Ok(v) = std::env::var("RANGE_CHECK_COLUMNS") {
            cfg.bounds.range_check_columns = v;
        }
        if let Ok(v) = std::env::var("RANGE_CHECK_MIN")
            && let Ok(f) = v.parse()
        {
            cfg.bounds.range_min = f;
        }
        if let Ok(v) = std::env::var("RANGE_CHECK_MAX")
            && let Ok(f) = v.parse()
        {
            cfg.bounds.range_max = f;
        }
        if let Ok(v) = std::env::var("NONNEG_COLUMNS") {
            cfg.bounds.nonneg_columns = v;
        }

        Ok(cfg)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        let cfg = Config::load().unwrap();
        assert_eq!(cfg.health_port, 8082);
        assert_eq!(cfg.bloom_size, 1_000_000);
        assert_eq!(cfg.bloom_fp_rate, 0.001);
        assert_eq!(
            cfg.kafka.brokers,
            "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092"
        );
        assert_eq!(cfg.kafka.input_topic, "raw");
        assert_eq!(cfg.kafka.output_topic, "validated");
    }

    #[test]
    fn test_bounds_config() {
        let bounds = BoundsConfig {
            range_check_columns: "value_a,value_b".to_string(),
            range_min: 0.0,
            range_max: 1_000_000.0,
            nonneg_columns: "value_c".to_string(),
        };

        assert_eq!(bounds.range_min, 0.0);
        assert_eq!(bounds.range_max, 1_000_000.0);
    }

    #[test]
    fn test_kafka_config_clone() {
        let kafka = KafkaConfig {
            brokers: "test:9092".to_string(),
            input_topic: "input".to_string(),
            output_topic: "output".to_string(),
            ..Default::default()
        };

        let cloned = kafka.clone();
        assert_eq!(kafka.brokers, cloned.brokers);
        assert_eq!(kafka.input_topic, cloned.input_topic);
        assert_eq!(kafka.output_topic, cloned.output_topic);
    }

    #[test]
    fn test_apply_security_noop_when_unset() {
        let kafka = KafkaConfig::default();
        let mut cc = ClientConfig::new();
        kafka.apply_security(&mut cc);
        assert!(cc.get("security.protocol").is_none());
    }

    #[test]
    fn test_apply_security_sets_sasl_ssl_fields() {
        let kafka = KafkaConfig {
            brokers: "b:9093".into(),
            input_topic: "raw".into(),
            output_topic: "validated".into(),
            security_protocol: Some("SASL_SSL".into()),
            sasl_mechanism: Some("SCRAM-SHA-512".into()),
            sasl_username: Some("user".into()),
            sasl_password: Some("pass".into()),
            ssl_ca_location: Some("/etc/kafka/ca/ca.crt".into()),
        };
        let mut cc = ClientConfig::new();
        kafka.apply_security(&mut cc);
        assert_eq!(cc.get("security.protocol"), Some("SASL_SSL"));
        assert_eq!(cc.get("sasl.mechanisms"), Some("SCRAM-SHA-512"));
        assert_eq!(cc.get("sasl.username"), Some("user"));
        assert_eq!(cc.get("sasl.password"), Some("pass"));
        assert_eq!(cc.get("ssl.ca.location"), Some("/etc/kafka/ca/ca.crt"));
    }

    #[test]
    fn test_schema_is_valid_json() {
        let cfg = Config::load().unwrap();
        let parsed: Result<serde_json::Value, _> = serde_json::from_str(&cfg.schema);
        assert!(parsed.is_ok());
    }

    #[test]
    fn test_schema_has_required_fields() {
        let cfg = Config::load().unwrap();
        let schema: serde_json::Value = serde_json::from_str(&cfg.schema).unwrap();

        let required = schema["required"].as_array().unwrap();
        assert!(required.iter().any(|v| v == "symbol"));
        assert!(required.iter().any(|v| v == "timestamp"));
    }
}
