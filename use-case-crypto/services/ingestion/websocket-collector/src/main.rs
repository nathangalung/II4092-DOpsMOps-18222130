//! use-case-crypto :: websocket-collector binary.
//!
//! Composes the platform's domain-agnostic machinery (config loader, Kafka
//! producer, health server, connection loop) with a Coinbase-specific
//! `MessageParser`. See coinbase.rs for the parser implementation.

use tokio::sync::mpsc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use websocket_collector::collectors::{generic::GenericCollector, Collector};
use websocket_collector::config::Config;
use websocket_collector::health;
use websocket_collector::producer::KafkaProducer;

mod coinbase;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting crypto-websocket-collector (use-case-crypto overlay)");

    let cfg = Config::load()?;

    let (tx, rx) = mpsc::channel(10000);

    let producer = KafkaProducer::new(&cfg.kafka)?;
    let _producer_handle = tokio::spawn(producer.run(rx));

    let mut handles = vec![];

    for source in &cfg.sources {
        if source.enabled {
            let parser = coinbase::CoinbaseParser::from_env();
            let collector = GenericCollector::new(source, tx.clone(), parser);
            let source_name = source.name.clone();
            handles.push(tokio::spawn(async move {
                if let Err(e) = collector.run().await {
                    error!("Collector error for {}: {}", source_name, e);
                }
            }));
        }
    }

    health::spawn_server_thread(cfg.health_port);

    tokio::signal::ctrl_c().await?;
    info!("Shutting down");

    Ok(())
}
