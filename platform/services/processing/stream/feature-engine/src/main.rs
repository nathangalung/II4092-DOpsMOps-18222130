use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

mod config;
mod engine;
mod grpc;

use config::Config;
use engine::FeatureEngine;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting Feature Engine");

    let cfg = Config::load()?;

    let engine = Arc::new(FeatureEngine::new(&cfg)?);

    let engine_clone = engine.clone();
    let _kafka_handle = tokio::spawn(async move {
        if let Err(e) = engine_clone.consume_loop().await {
            error!("Kafka consumer error: {}", e);
        }
    });

    let _grpc_handle = tokio::spawn(grpc::run_server(cfg.grpc_port, engine.clone()));
    let _health_handle = tokio::spawn(run_health(cfg.health_port));

    tokio::signal::ctrl_c().await?;
    info!("Shutting down");

    Ok(())
}

async fn run_health(port: u16) -> anyhow::Result<()> {
    use tokio::io::AsyncWriteExt;
    use tokio::net::TcpListener;

    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    info!("Health server on port {}", port);

    loop {
        let (mut socket, _) = listener.accept().await?;
        let response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
        let _ = socket.write_all(response.as_bytes()).await;
    }
}
