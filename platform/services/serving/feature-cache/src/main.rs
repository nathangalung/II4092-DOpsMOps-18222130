use std::sync::Arc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

mod cache;
mod config;
mod grpc;

use cache::FeatureStore;
use config::Config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting Feature Cache");

    let cfg = Config::load()?;

    let store = Arc::new(FeatureStore::new(&cfg)?);

    let store_clone = store.clone();
    let _sync_handle = tokio::spawn(async move {
        if let Err(e) = store_clone.sync_from_valkey().await {
            error!("Valkey sync error: {}", e);
        }
    });

    let _grpc_handle = tokio::spawn(grpc::run_server(cfg.grpc_port, store.clone()));
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
