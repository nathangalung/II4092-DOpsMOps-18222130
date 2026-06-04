//! High-performance Kafka producer
//! Batched writes with 100us flush interval

use crate::collectors::Record;
use crate::config::KafkaConfig;
use crate::health;
use anyhow::Result;
use futures::future::join_all;
use rdkafka::client::ClientContext;
use rdkafka::error::KafkaError;
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::{debug, error, warn};

/// Custom librdkafka client context that surfaces client-level errors (broker
/// transport failures, leader-resolution errors, etc.) into our tracing logs.
///
/// Only `error()` is overridden. The default `log()` impl is intentionally
/// preserved: it forwards librdkafka WARN lines — including the
/// "leader-not-found" message that is the signature of the post-broker-restart
/// producer wedge (#468) — to the `librdkafka` tracing target. Overriding
/// `log()` would silence that signal.
struct LoggingContext;

impl ClientContext for LoggingContext {
    fn error(&self, error: KafkaError, reason: &str) {
        warn!("kafka client error: {error} ({reason})");
    }
}

pub struct KafkaProducer {
    producer: FutureProducer<LoggingContext>,
    topic: String,
    batch_size: usize,
    flush_interval: Duration,
}

impl KafkaProducer {
    pub fn new(config: &KafkaConfig) -> Result<Self> {
        let mut cc = ClientConfig::new();
        cc.set("bootstrap.servers", &config.brokers)
            // 120s (not 5s): on a single-node KRaft cluster the controller can
            // stall multi-second on metadata-log fsync under IO pressure, which
            // surfaced spurious MessageTimedOut on a 5s budget even when the
            // broker was healthy. 120s rides through transient stalls while the
            // librdkafka queue (queue.buffering.max.messages default) bounds RAM.
            .set("message.timeout.ms", "120000")
            // zstd: universally supported by librdkafka builds + broker default
            // (Strimzi platform-kafka spec.kafka.config.compression.type=zstd).
            // lz4 here triggered consumer-side "Decompression (codec 0x4) ...
            // Not implemented" on the Rust feature-engine whose rdkafka crate
            // was built without lz4-sys.
            .set("compression.type", "zstd")
            .set("linger.ms", "5")
            .set("batch.size", "65536")
            .set("acks", "1");
        config.apply_security(&mut cc);
        let producer: FutureProducer<LoggingContext> = cc.create_with_context(LoggingContext)?;

        Ok(Self {
            producer,
            topic: config.topic.clone(),
            batch_size: config.batch_size,
            flush_interval: Duration::from_millis(config.flush_interval_ms),
        })
    }

    /// Run producer loop
    pub async fn run(self, mut rx: mpsc::Receiver<Record>) {
        // Seed the delivery clock so the `/live` probe treats a freshly-started,
        // not-yet-producing collector as healthy until it actually attempts (and
        // fails) sends. See health::liveness_wedged for the decision logic.
        health::seed_delivery_clock();

        let mut batch: Vec<Record> = Vec::with_capacity(self.batch_size);
        let mut interval = tokio::time::interval(self.flush_interval);

        loop {
            tokio::select! {
                Some(record) = rx.recv() => {
                    batch.push(record);
                    if batch.len() >= self.batch_size {
                        self.flush(&mut batch);
                    }
                }
                _ = interval.tick() => {
                    if !batch.is_empty() {
                        self.flush(&mut batch);
                    }
                }
            }
        }
    }

    /// Flush a batch to Kafka without blocking the run loop.
    ///
    /// Each record is *enqueued* synchronously via `send_result` (librdkafka
    /// copies key/payload at enqueue, so the borrows end here and the returned
    /// `DeliveryFuture`s own their data). Delivery resolution is then moved to a
    /// detached task so the select loop keeps draining the channel.
    ///
    /// This decouple is the core of the #468 fix: the previous code awaited each
    /// `send(...)` inline, which serialized delivery per-message and — once the
    /// producer wedged after a broker restart — stalled the loop while every
    /// message silently expired at `message.timeout.ms`. Enqueue + detached
    /// resolution keeps throughput up and feeds the delivery-health clock
    /// (`record_attempt` / `record_success` / `record_failure`) that gates the
    /// `/live` probe so a persistent wedge self-heals via pod restart.
    fn flush(&self, batch: &mut Vec<Record>) {
        let count = batch.len();
        debug!("Flushing {} records", count);

        let mut futures = Vec::with_capacity(count);
        for record in batch.drain(..) {
            let key = record.symbol.clone();
            let payload = match serde_json::to_string(&record) {
                Ok(p) => p,
                Err(e) => {
                    error!("Serialize error: {}", e);
                    continue;
                }
            };

            let topic = record.target_topic.as_deref().unwrap_or(&self.topic);
            let kafka_record = FutureRecord::to(topic).key(&key).payload(&payload);

            health::record_attempt();
            match self.producer.send_result(kafka_record) {
                Ok(fut) => futures.push(fut),
                Err((e, _)) => {
                    health::record_failure();
                    if health::should_log_kafka_error() {
                        error!("Kafka enqueue error: {}", e);
                    }
                }
            }
        }

        if !futures.is_empty() {
            tokio::spawn(async move {
                for result in join_all(futures).await {
                    match result {
                        Ok(Ok(_)) => health::record_success(),
                        Ok(Err((e, _))) => {
                            health::record_failure();
                            if health::should_log_kafka_error() {
                                error!("Kafka delivery error: {}", e);
                            }
                        }
                        // Producer dropped before delivery resolved — process is
                        // shutting down; nothing actionable.
                        Err(_canceled) => {}
                    }
                }
            });
        }

        debug!("Flushed {} records", count);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kafka_config_values() {
        let config = KafkaConfig {
            brokers: "localhost:9092".to_string(),
            topic: "test-topic".to_string(),
            batch_size: 500,
            flush_interval_ms: 100,
            ..Default::default()
        };

        assert_eq!(config.brokers, "localhost:9092");
        assert_eq!(config.topic, "test-topic");
        assert_eq!(config.batch_size, 500);
        assert_eq!(config.flush_interval_ms, 100);
    }

    #[test]
    fn test_record_serialization_for_kafka() {
        use std::collections::BTreeMap;

        let record = Record {
            symbol: "SYM1".to_string(),
            timestamp: 1234567890,
            source: "test".to_string(),
            target_topic: None,
            values: BTreeMap::from([
                ("value_1".to_string(), 105.0),
                ("value_2".to_string(), 100.0),
                ("value_3".to_string(), 110.0),
                ("value_4".to_string(), 90.0),
                ("value_5".to_string(), 1000.0),
            ]),
        };

        let json = serde_json::to_string(&record).unwrap();
        assert!(json.contains("SYM1"));
        assert!(json.contains("1234567890"));
        assert!(json.contains("\"value_1\":105"));
    }

    #[test]
    fn test_batch_capacity() {
        let batch_size = 500;
        let batch: Vec<Record> = Vec::with_capacity(batch_size);
        assert_eq!(batch.capacity(), 500);
        assert_eq!(batch.len(), 0);
    }

    #[test]
    fn test_duration_conversion() {
        let duration = Duration::from_millis(100);
        assert_eq!(duration.as_millis(), 100);
    }
}
