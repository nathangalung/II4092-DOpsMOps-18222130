pub mod indicators;
pub mod state;

#[cfg(test)]
mod tests;

use chrono::{DateTime, Utc};
use dashmap::DashMap;
use futures::StreamExt;
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use rdkafka::Message;
use serde::de::{self, Deserializer};
use std::collections::BTreeMap;
use tracing::{debug, error, info};

use crate::config::{Config, IndicatorConfig};
use indicators::Features;
use state::SymbolState;

pub struct FeatureEngine {
    consumer: StreamConsumer,
    producer: FutureProducer,
    states: DashMap<String, SymbolState>,
    output_topic: String,
    redis_client: redis::Client,
    ttl: u64,
    indicator_config: IndicatorConfig,
    primary_value_field: String,
    secondary_value_field: String,
}

impl FeatureEngine {
    pub fn new(cfg: &Config) -> anyhow::Result<Self> {
        let mut consumer_cfg = ClientConfig::new();
        consumer_cfg
            .set("bootstrap.servers", &cfg.kafka.brokers)
            .set("group.id", &cfg.kafka.group_id)
            .set("auto.offset.reset", "latest")
            .set("enable.auto.commit", "true");
        cfg.kafka.apply_security(&mut consumer_cfg);
        let consumer: StreamConsumer = consumer_cfg.create()?;

        consumer.subscribe(&[&cfg.kafka.input_topic])?;

        let mut producer_cfg = ClientConfig::new();
        producer_cfg
            .set("bootstrap.servers", &cfg.kafka.brokers)
            .set("message.timeout.ms", "5000");
        cfg.kafka.apply_security(&mut producer_cfg);
        let producer: FutureProducer = producer_cfg.create()?;

        let redis_client = redis::Client::open(cfg.redis.url.as_str())?;

        let window_size = cfg.indicators.window_size;
        let states = DashMap::new();
        for symbol in &cfg.symbols {
            states.insert(symbol.clone(), SymbolState::new(window_size));
        }

        // Configurable field names — use-case sets these via env/config
        let primary_value_field = std::env::var("PRIMARY_VALUE_FIELD")
            .unwrap_or_else(|_| "value_1".to_string());
        let secondary_value_field = std::env::var("SECONDARY_VALUE_FIELD")
            .unwrap_or_else(|_| "value_2".to_string());

        Ok(Self {
            consumer,
            producer,
            states,
            output_topic: cfg.kafka.output_topic.clone(),
            redis_client,
            ttl: cfg.redis.ttl_seconds,
            indicator_config: IndicatorConfig {
                rolling_mean_periods: cfg.indicators.rolling_mean_periods.clone(),
                exp_avg_periods: cfg.indicators.exp_avg_periods.clone(),
                momentum_period: cfg.indicators.momentum_period,
                trend_convergence_enabled: cfg.indicators.trend_convergence_enabled,
                deviation_bands_period: cfg.indicators.deviation_bands_period,
                deviation_bands_enabled: cfg.indicators.deviation_bands_enabled,
                secondary_avg_period: cfg.indicators.secondary_avg_period,
                dispersion_period: cfg.indicators.dispersion_period,
                window_size: cfg.indicators.window_size,
            },
            primary_value_field,
            secondary_value_field,
        })
    }

    pub async fn consume_loop(&self) -> anyhow::Result<()> {
        info!("Starting Kafka consumer loop");

        let mut stream = self.consumer.stream();

        while let Some(result) = stream.next().await {
            match result {
                Ok(msg) => {
                    if let Some(payload) = msg.payload()
                        && let Err(e) = self.process_message(payload).await
                    {
                        error!("Process error: {}", e);
                    }
                }
                Err(e) => error!("Kafka error: {}", e),
            }
        }

        Ok(())
    }

    async fn process_message(&self, payload: &[u8]) -> anyhow::Result<()> {
        let tick: Tick = serde_json::from_slice(payload)?;

        let mut state = self
            .states
            .entry(tick.symbol.clone())
            .or_insert(SymbolState::new(self.indicator_config.window_size));

        state.update(&tick, &self.primary_value_field, &self.secondary_value_field);
        let features = state.compute_features(&self.indicator_config);

        self.cache_features(&tick.symbol, &features).await?;

        // Convert unix timestamp to ISO 8601 for ClickHouse DateTime64 compatibility
        let ts_str = DateTime::from_timestamp(tick.timestamp, 0)
            .map(|dt| dt.format("%Y-%m-%d %H:%M:%S%.3f").to_string())
            .unwrap_or_else(|| tick.timestamp.to_string());

        let output = FeatureOutput {
            symbol: tick.symbol,
            timestamp: ts_str,
            original_values: tick.values,
            features,
        };

        let payload = serde_json::to_vec(&output)?;
        self.producer
            .send(
                FutureRecord::to(&self.output_topic)
                    .payload(&payload)
                    .key(&output.symbol),
                std::time::Duration::from_secs(5),
            )
            .await
            .map_err(|(e, _)| anyhow::anyhow!("Kafka send error: {}", e))?;

        debug!("Processed {}", output.symbol);
        Ok(())
    }

    async fn cache_features(&self, symbol: &str, features: &Features) -> anyhow::Result<()> {
        let mut conn = self.redis_client.get_multiplexed_async_connection().await?;
        let key = format!("features:{}", symbol);
        let value = serde_json::to_string(features)?;

        redis::cmd("SETEX")
            .arg(&key)
            .arg(self.ttl)
            .arg(&value)
            .query_async::<()>(&mut conn)
            .await?;

        Ok(())
    }

    #[allow(dead_code)]
    pub fn get_features(&self, symbol: &str) -> Option<Features> {
        self.states
            .get(symbol)
            .map(|s| s.compute_features(&self.indicator_config))
    }
}

/// Deserialize timestamp from either ISO 8601 string or unix epoch integer.
fn deserialize_flexible_timestamp<'de, D>(deserializer: D) -> Result<i64, D::Error>
where
    D: Deserializer<'de>,
{
    struct TimestampVisitor;

    impl<'de> de::Visitor<'de> for TimestampVisitor {
        type Value = i64;

        fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
            formatter.write_str("an ISO 8601 timestamp string or unix epoch integer")
        }

        fn visit_i64<E: de::Error>(self, v: i64) -> Result<i64, E> {
            Ok(v)
        }

        fn visit_u64<E: de::Error>(self, v: u64) -> Result<i64, E> {
            Ok(v as i64)
        }

        fn visit_str<E: de::Error>(self, v: &str) -> Result<i64, E> {
            v.parse::<DateTime<Utc>>()
                .map(|dt| dt.timestamp())
                .map_err(de::Error::custom)
        }
    }

    deserializer.deserialize_any(TimestampVisitor)
}

/// Generic tick — dynamic key-value fields instead of hardcoded column names.
/// The primary value and volume fields are configured per use-case.
#[derive(Debug, serde::Deserialize)]
pub struct Tick {
    pub symbol: String,
    #[serde(deserialize_with = "deserialize_flexible_timestamp")]
    pub timestamp: i64,
    /// Dynamic numeric fields — keys are field names from the data source.
    #[serde(flatten)]
    pub values: BTreeMap<String, serde_json::Value>,
}

impl Tick {
    /// Get a numeric value by field name.
    pub fn get_f64(&self, field: &str) -> Option<f64> {
        self.values.get(field).and_then(|v| v.as_f64())
    }
}

#[derive(Debug, serde::Serialize)]
pub struct FeatureOutput {
    pub symbol: String,
    pub timestamp: String,
    /// Flatten original tick values and computed features to top-level fields,
    /// so downstream sinks (e.g., ClickHouse JSONEachRow) receive flat JSON.
    #[serde(flatten)]
    pub original_values: BTreeMap<String, serde_json::Value>,
    #[serde(flatten)]
    pub features: Features,
}
