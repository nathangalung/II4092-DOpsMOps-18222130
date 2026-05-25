//! Rust data quality validator
//! Ultra-low latency: <50us per record

use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{error, info};
use tracing_subscriber::EnvFilter;

mod config;
mod producer;
mod validator;

use config::Config;
use producer::KafkaProducer;
use validator::{BoundsChecker, DedupFilter, SchemaValidator, Validator};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    info!("Starting data validator");

    let cfg = Config::load()?;

    // Create validator pipeline
    let schema = SchemaValidator::new(&cfg.schema)?;
    let dedup = DedupFilter::new(cfg.bloom_size, cfg.bloom_fp_rate);
    let bounds = BoundsChecker::new(&cfg.bounds);

    let validator = Arc::new(Validator::new(schema, dedup, bounds));

    // Kafka consumer -> validator -> producer
    let (tx, rx) = mpsc::channel(10000);
    let producer = KafkaProducer::new(&cfg.kafka)?;

    // Start producer
    let _prod_handle = tokio::spawn(producer.run(rx));

    // Start consumer
    let _cons_handle = tokio::spawn(consume_and_validate(cfg.clone(), validator, tx));

    // Health server - run in separate thread with actix runtime
    let health_port = cfg.health_port;
    std::thread::spawn(move || {
        let rt = actix_rt::Runtime::new().unwrap();
        rt.block_on(run_health(health_port)).unwrap();
    });

    tokio::signal::ctrl_c().await?;
    Ok(())
}

async fn consume_and_validate(
    cfg: Config,
    validator: Arc<Validator>,
    tx: mpsc::Sender<Vec<u8>>,
) -> anyhow::Result<()> {
    use futures::StreamExt;
    use rdkafka::consumer::{Consumer, StreamConsumer};
    use rdkafka::ClientConfig;
    use rdkafka::Message;

    let mut consumer_cfg = ClientConfig::new();
    consumer_cfg
        .set("bootstrap.servers", &cfg.kafka.brokers)
        .set("group.id", "validator")
        .set("auto.offset.reset", "earliest");
    cfg.kafka.apply_security(&mut consumer_cfg);
    let consumer: StreamConsumer = consumer_cfg.create()?;

    // KAFKA_TOPIC accepts a comma-separated list so a single validator
    // Deployment can fan-in from multiple raw sources. Trimming guards
    // against whitespace from ConfigMap-templated values.
    let topics: Vec<&str> = cfg
        .kafka
        .input_topic
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    consumer.subscribe(&topics)?;
    info!(
        "Consuming from {:?} -> producing to {}",
        topics, cfg.kafka.output_topic
    );

    let mut count: u64 = 0;
    let mut valid_count: u64 = 0;
    let mut stream = consumer.stream();
    while let Some(result) = stream.next().await {
        match result {
            Ok(msg) => {
                if let Some(payload) = msg.payload() {
                    count += 1;
                    let original = payload.to_vec();
                    let mut parse_buf = original.clone();
                    match validator.validate(&mut parse_buf) {
                        Ok(true) => {
                            valid_count += 1;
                            let _ = tx.send(original).await;
                        }
                        Ok(false) => {}
                        Err(e) => error!("Validation error: {}", e),
                    }
                    if count.is_multiple_of(1000) {
                        info!("Processed {count} records, {valid_count} valid");
                    }
                }
            }
            Err(e) => error!("Kafka error: {}", e),
        }
    }

    Ok(())
}

async fn run_health(port: u16) -> std::io::Result<()> {
    use actix_web::{web, App, HttpResponse, HttpServer};

    HttpServer::new(|| {
        App::new()
            .route(
                "/health",
                web::get().to(|| async { HttpResponse::Ok().body("ok") }),
            )
            .route(
                "/ready",
                web::get().to(|| async { HttpResponse::Ok().body("ready") }),
            )
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}
