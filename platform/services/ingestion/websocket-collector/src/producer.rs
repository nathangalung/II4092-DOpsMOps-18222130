//! High-performance Kafka producer
//! Batched writes with 100us flush interval

use crate::collectors::Record;
use crate::config::KafkaConfig;
use anyhow::Result;
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::{debug, error};

pub struct KafkaProducer {
    producer: FutureProducer,
    topic: String,
    batch_size: usize,
    flush_interval: Duration,
}

impl KafkaProducer {
    pub fn new(config: &KafkaConfig) -> Result<Self> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("message.timeout.ms", "5000")
            .set("compression.type", "lz4")
            .set("linger.ms", "5")
            .set("batch.size", "65536")
            .set("acks", "1")
            .create()?;

        Ok(Self {
            producer,
            topic: config.topic.clone(),
            batch_size: config.batch_size,
            flush_interval: Duration::from_millis(config.flush_interval_ms),
        })
    }

    /// Run producer loop
    pub async fn run(self, mut rx: mpsc::Receiver<Record>) {
        let mut batch: Vec<Record> = Vec::with_capacity(self.batch_size);
        let mut interval = tokio::time::interval(self.flush_interval);

        loop {
            tokio::select! {
                Some(record) = rx.recv() => {
                    batch.push(record);
                    if batch.len() >= self.batch_size {
                        self.flush(&mut batch).await;
                    }
                }
                _ = interval.tick() => {
                    if !batch.is_empty() {
                        self.flush(&mut batch).await;
                    }
                }
            }
        }
    }

    /// Flush batch to Kafka
    async fn flush(&self, batch: &mut Vec<Record>) {
        let count = batch.len();
        debug!("Flushing {} records", count);

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

            if let Err((e, _)) = self
                .producer
                .send(kafka_record, Duration::from_secs(1))
                .await
            {
                error!("Kafka send error: {}", e);
            }
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
