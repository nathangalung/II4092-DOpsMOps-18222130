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
        let mut cc = ClientConfig::new();
        cc.set("bootstrap.servers", &config.brokers)
            // 120s (not 5s): the single-node KRaft controller can stall
            // multi-second on metadata-log fsync under IO pressure, surfacing
            // spurious MessageTimedOut on a 5s budget. 120s absorbs the stalls.
            .set("message.timeout.ms", "120000")
            // zstd: universally supported by librdkafka + matches Strimzi broker
            // `compression.type=zstd`. lz4 here previously triggered consumer
            // "Decompression (codec 0x4) ... Not implemented" on rdkafka
            // crate builds that omit lz4-sys (seen on the since-retired
            // feature-engine image).
            .set("compression.type", "zstd");
        config.apply_security(&mut cc);
        let producer: FutureProducer = cc.create()?;

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
