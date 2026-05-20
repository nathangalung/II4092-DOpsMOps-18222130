//! Platform-default WebSocket collector binary.
//! Pairs `GenericCollector` with `DefaultTickerParser` (source-agnostic).
//! Use-case overlays provide their own binaries that swap in custom parsers.

use tokio::sync::mpsc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

use websocket_collector::collectors::{
    generic::{DefaultTickerParser, GenericCollector},
    Collector,
};
use websocket_collector::config::Config;
use websocket_collector::health;
use websocket_collector::producer::KafkaProducer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting WebSocket collector (platform default)");

    let cfg = Config::load()?;

    let (tx, rx) = mpsc::channel(10000);

    let producer = KafkaProducer::new(&cfg.kafka)?;
    let _producer_handle = tokio::spawn(producer.run(rx));

    let mut handles = vec![];

    for source in &cfg.sources {
        if source.enabled {
            let collector = GenericCollector::new(source, tx.clone(), DefaultTickerParser);
            let source_name = source.name.clone();
            handles.push(tokio::spawn(async move {
                if let Err(e) = collector.run().await {
                    error!("Collector error for {}: {}", source_name, e);
                }
            }));
        }
    }

    health::spawn_server_thread(cfg.health_port);

    // Wait for shutdown
    tokio::signal::ctrl_c().await?;
    info!("Shutting down");

    Ok(())
}
