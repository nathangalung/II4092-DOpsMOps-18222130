//! Health check server

use actix_web::{web, App, HttpResponse, HttpServer};
use prometheus::{register_counter, register_gauge, Counter, Encoder, Gauge, TextEncoder};
use std::sync::LazyLock;

#[allow(dead_code)]
static MESSAGES_RECEIVED: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("collector_messages_total", "Total messages received").unwrap()
});

#[allow(dead_code)]
static KAFKA_SENT: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("collector_kafka_sent_total", "Messages sent to Kafka").unwrap()
});

#[allow(dead_code)]
static CONNECTED: LazyLock<Gauge> = LazyLock::new(|| {
    register_gauge!("collector_connected", "WebSocket connection status").unwrap()
});

async fn health() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "websocket-collector"
    }))
}

async fn ready() -> HttpResponse {
    HttpResponse::Ok().body("ready")
}

async fn live() -> HttpResponse {
    HttpResponse::Ok().body("live")
}

async fn metrics() -> HttpResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body(buffer)
}

pub async fn run_server(port: u16) -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/health", web::get().to(health))
            .route("/ready", web::get().to(ready))
            .route("/live", web::get().to(live))
            .route("/metrics", web::get().to(metrics))
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

/// Spawn the health server on a dedicated OS thread with its own actix runtime.
/// Returned so binaries don't need to take a direct `actix_rt` dependency.
pub fn spawn_server_thread(port: u16) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        let rt = actix_rt::Runtime::new().expect("failed to create actix runtime for health server");
        if let Err(e) = rt.block_on(run_server(port)) {
            eprintln!("health server exited with error: {e}");
        }
    })
}

// Metric helpers -- called by collectors/producer at runtime
#[allow(dead_code)]
pub fn inc_messages() {
    MESSAGES_RECEIVED.inc();
}

#[allow(dead_code)]
pub fn inc_kafka_sent() {
    KAFKA_SENT.inc();
}

#[allow(dead_code)]
pub fn set_connected(val: f64) {
    CONNECTED.set(val);
}
