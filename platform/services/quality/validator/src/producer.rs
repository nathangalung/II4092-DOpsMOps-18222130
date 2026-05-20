//! Kafka producer

use crate::config::KafkaConfig;
use anyhow::Result;
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use std::time::Duration;
use tokio::sync::mpsc;
use tracing::error;

pub struct KafkaProducer {
    producer: FutureProducer,
    topic: String,
}

impl KafkaProducer {
    pub fn new(config: &KafkaConfig) -> Result<Self> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", &config.brokers)
            .set("message.timeout.ms", "5000")
            .set("compression.type", "lz4")
            .create()?;

        Ok(Self {
            producer,
            topic: config.output_topic.clone(),
        })
    }

    pub async fn run(self, mut rx: mpsc::Receiver<Vec<u8>>) {
        while let Some(data) = rx.recv().await {
            let record: FutureRecord<'_, (), _> = FutureRecord::to(&self.topic).payload(&data);

            if let Err((e, _)) = self.producer.send(record, Duration::from_secs(1)).await {
                error!("Kafka send error: {}", e);
            }
        }
    }
}
