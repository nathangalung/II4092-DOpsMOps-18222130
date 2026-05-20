use std::sync::Arc;
use tracing::info;
use tracing_subscriber::EnvFilter;

mod cache;
mod config;
mod grpc;
mod server;

use cache::CacheLayer;
use config::Config;
use grpc::InferenceClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting Serving Gateway");

    let cfg = Config::load()?;

    let cache = Arc::new(CacheLayer::new(&cfg.cache)?);
    let inference_client = Arc::new(InferenceClient::new(&cfg.inference).await?);

    // Run HTTP server in separate thread with actix runtime
    let http_port = cfg.http_port;
    let http_cache = cache.clone();
    let http_inference = inference_client.clone();
    std::thread::spawn(move || {
        let rt = actix_rt::Runtime::new().unwrap();
        rt.block_on(server::run_http_server(
            http_port,
            http_cache,
            http_inference,
        ))
        .unwrap();
    });

    let _ws_handle = tokio::spawn(server::run_ws_server(cfg.ws_port, cache.clone()));

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
