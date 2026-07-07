//! Health check server.
//!
//! Exposes `/health` (process alive), `/ready` (accepting work), `/live`
//! (liveness - delivery-gated) and `/metrics` (Prometheus).
//!
//! The `/live` endpoint reports the *delivery* health of the Kafka producer,
//! not merely process liveness. librdkafka can wedge after a broker
//! disruption (e.g. failing to re-resolve partition leaders) in a state where
//! it still accepts enqueues but never delivers - every message then expires at
//! `message.timeout.ms` as `MessageTimedOut`. That failure is invisible to a
//! plain process-liveness probe, so the producer stalls indefinitely until
//! something restarts it. Gating `/live` on *successful delivery* lets the
//! kubelet livenessProbe restart the pod (a fresh producer re-resolves leaders
//! cleanly), giving the workload a self-heal path for that class of wedge.
//!
//! The staleness threshold is configurable (`KAFKA_DELIVERY_STALENESS_MS`,
//! default 300000 = 2.5x the default `message.timeout.ms`) so it tolerates
//! transient broker restarts without flapping but catches a persistent wedge.

use actix_web::{web, App, HttpResponse, HttpServer};
use prometheus::{register_counter, register_gauge, Counter, Encoder, Gauge, TextEncoder};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::LazyLock;
use std::time::{SystemTime, UNIX_EPOCH};

#[allow(dead_code)]
static MESSAGES_RECEIVED: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("collector_messages_total", "Total messages received").unwrap()
});

static KAFKA_SENT: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!("collector_kafka_sent_total", "Messages delivered to Kafka").unwrap()
});

static KAFKA_FAILED: LazyLock<Counter> = LazyLock::new(|| {
    register_counter!(
        "collector_kafka_failed_total",
        "Messages that failed to enqueue or deliver to Kafka"
    )
    .unwrap()
});

#[allow(dead_code)]
static CONNECTED: LazyLock<Gauge> = LazyLock::new(|| {
    register_gauge!("collector_connected", "WebSocket connection status").unwrap()
});

/// Epoch-millis of the last successful Kafka delivery (and last send attempt).
/// Seeded to process start so an idle producer is never reported unhealthy.
static LAST_SUCCESS_MS: AtomicI64 = AtomicI64::new(0);
static LAST_ATTEMPT_MS: AtomicI64 = AtomicI64::new(0);
/// Throttle gate for delivery-error logging (epoch-millis of last emission).
static LAST_ERROR_LOG_MS: AtomicI64 = AtomicI64::new(0);

/// How long the producer may go without a *successful* delivery - while it is
/// still attempting sends - before `/live` reports unhealthy. Override via
/// `KAFKA_DELIVERY_STALENESS_MS`; defaults to 300000ms.
static STALENESS_MS: LazyLock<i64> = LazyLock::new(|| {
    std::env::var("KAFKA_DELIVERY_STALENESS_MS")
        .ok()
        .and_then(|v| v.parse::<i64>().ok())
        .filter(|&v| v > 0)
        .unwrap_or(300_000)
});

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// Pure liveness decision, extracted so it can be unit-tested without a broker.
///
/// The producer is "wedged" only when BOTH hold:
///   - sends have been attempted since the last success (`attempting`), and
///   - no success has landed within the staleness window (`stale`).
///
/// An idle producer (no recent attempts) is healthy even if its last success is
/// old; an in-flight producer (recent attempt, recent success) is healthy.
fn liveness_wedged(now_ms: i64, last_success_ms: i64, last_attempt_ms: i64, staleness_ms: i64) -> bool {
    let stale = now_ms - last_success_ms > staleness_ms;
    let attempting = last_attempt_ms > last_success_ms;
    stale && attempting
}

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
    let now = now_ms();
    let last_success = LAST_SUCCESS_MS.load(Ordering::Relaxed);
    let last_attempt = LAST_ATTEMPT_MS.load(Ordering::Relaxed);
    if liveness_wedged(now, last_success, last_attempt, *STALENESS_MS) {
        let stalled_s = (now - last_success) / 1000;
        return HttpResponse::ServiceUnavailable().body(format!(
            "kafka delivery stalled: no successful delivery for {stalled_s}s while sends are being attempted"
        ));
    }
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

// Delivery-health hooks - called by the producer at runtime.

/// Seed the delivery clock at startup so a freshly-started, not-yet-producing
/// collector is reported healthy until it actually attempts (and fails) sends.
pub fn seed_delivery_clock() {
    let now = now_ms();
    LAST_SUCCESS_MS.store(now, Ordering::Relaxed);
    LAST_ATTEMPT_MS.store(now, Ordering::Relaxed);
}

/// Record that a send was attempted (enqueued or rejected).
pub fn record_attempt() {
    LAST_ATTEMPT_MS.store(now_ms(), Ordering::Relaxed);
}

/// Record a confirmed delivery to the broker.
pub fn record_success() {
    LAST_SUCCESS_MS.store(now_ms(), Ordering::Relaxed);
    KAFKA_SENT.inc();
}

/// Record an enqueue or delivery failure.
pub fn record_failure() {
    KAFKA_FAILED.inc();
}

/// Best-effort rate limiter for error logging (at most once per 10s) so a total
/// producer wedge surfaces in logs without flooding them. A benign race may let
/// a couple of extra lines through, which is acceptable.
pub fn should_log_kafka_error() -> bool {
    let now = now_ms();
    let last = LAST_ERROR_LOG_MS.load(Ordering::Relaxed);
    if now - last >= 10_000 {
        LAST_ERROR_LOG_MS.store(now, Ordering::Relaxed);
        true
    } else {
        false
    }
}

// Metric helpers -- called by collectors at runtime
#[allow(dead_code)]
pub fn inc_messages() {
    MESSAGES_RECEIVED.inc();
}

#[allow(dead_code)]
pub fn set_connected(val: f64) {
    CONNECTED.set(val);
}

#[cfg(test)]
mod tests {
    use super::liveness_wedged;

    const STALE: i64 = 300_000;

    #[test]
    fn idle_is_not_wedged() {
        let now = 1_000_000;
        // No attempt since the last success, even though success is very old.
        assert!(!liveness_wedged(now, 100_000, 100_000, STALE));
        // Last attempt predates last success (idle after a success).
        assert!(!liveness_wedged(now, 100_000, 50_000, STALE));
    }

    #[test]
    fn in_flight_is_not_wedged() {
        let now = 1_000_000;
        // Attempted after the last success, but success is recent (< staleness):
        // this is the steady-state case that must NOT trigger a restart.
        assert!(!liveness_wedged(now, now - 1_000, now - 500, STALE));
    }

    #[test]
    fn stale_and_attempting_is_wedged() {
        let now = 1_000_000;
        // 301s since last success, with a more recent attempt, so wedged.
        assert!(liveness_wedged(now, now - 301_000, now - 1_000, STALE));
    }

    #[test]
    fn recovery_resets() {
        let now = 1_000_000;
        // A fresh success (now) clears the wedge even with an older attempt.
        assert!(!liveness_wedged(now, now, now - 1_000, STALE));
    }

    #[test]
    fn boundary_at_threshold_is_not_wedged() {
        let now = 1_000_000;
        // Exactly at the threshold is not yet stale (strict `>`).
        assert!(!liveness_wedged(now, now - STALE, now - 1_000, STALE));
    }
}
