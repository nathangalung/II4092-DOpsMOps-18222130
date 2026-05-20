use actix_web::{web, App, HttpResponse, HttpServer, Responder};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::info;

use crate::cache::CacheLayer;
use crate::grpc::InferenceClient;

pub struct AppState {
    pub cache: Arc<CacheLayer>,
    pub inference: Arc<InferenceClient>,
}

#[derive(Deserialize)]
pub struct PredictRequest {
    pub symbol: String,
    pub features: Vec<f64>,
}

#[derive(Serialize, Deserialize)]
pub struct PredictResponse {
    pub symbol: String,
    pub prediction: f64,
    pub confidence: f64,
    pub direction: String,
    pub cached: bool,
}

async fn predict(state: web::Data<AppState>, req: web::Json<PredictRequest>) -> impl Responder {
    let cache_key = format!("pred:{}:{:?}", req.symbol, req.features);

    if let Some(cached) = state.cache.get(&cache_key).await
        && let Ok(resp) = serde_json::from_str::<PredictResponse>(&cached)
    {
        return HttpResponse::Ok().json(PredictResponse {
            cached: true,
            ..resp
        });
    }

    match state.inference.predict(&req.symbol, &req.features).await {
        Ok((prediction, confidence)) => {
            let direction = if prediction > 0.0 { "UP" } else { "DOWN" };
            let resp = PredictResponse {
                symbol: req.symbol.clone(),
                prediction,
                confidence,
                direction: direction.to_string(),
                cached: false,
            };

            if let Ok(json) = serde_json::to_string(&resp) {
                let _ = state.cache.set(&cache_key, &json).await;
            }

            HttpResponse::Ok().json(resp)
        }
        Err(e) => HttpResponse::InternalServerError().body(format!("Inference error: {}", e)),
    }
}

async fn health() -> impl Responder {
    HttpResponse::Ok().body("OK")
}

async fn metrics(state: web::Data<AppState>) -> impl Responder {
    let stats = state.cache.stats();
    HttpResponse::Ok().json(stats)
}

pub async fn run_http_server(
    port: u16,
    cache: Arc<CacheLayer>,
    inference: Arc<InferenceClient>,
) -> anyhow::Result<()> {
    let state = web::Data::new(AppState { cache, inference });

    info!("HTTP server listening on port {}", port);

    HttpServer::new(move || {
        App::new()
            .app_data(state.clone())
            .route("/health", web::get().to(health))
            .route("/metrics", web::get().to(metrics))
            .route("/predict", web::post().to(predict))
    })
    .bind(format!("0.0.0.0:{}", port))?
    .run()
    .await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_predict_request_creation() {
        let req = PredictRequest {
            symbol: "SYMBOL-A".to_string(),
            features: vec![1.0, 2.0, 3.0],
        };

        assert_eq!(req.symbol, "SYMBOL-A");
        assert_eq!(req.features.len(), 3);
    }

    #[test]
    fn test_predict_response_creation() {
        let resp = PredictResponse {
            symbol: "SYMBOL-A".to_string(),
            prediction: 0.05,
            confidence: 0.85,
            direction: "UP".to_string(),
            cached: false,
        };

        assert_eq!(resp.symbol, "SYMBOL-A");
        assert_eq!(resp.prediction, 0.05);
        assert_eq!(resp.confidence, 0.85);
        assert_eq!(resp.direction, "UP");
        assert!(!resp.cached);
    }

    #[test]
    fn test_predict_response_serialization() {
        let resp = PredictResponse {
            symbol: "SYMBOL-B".to_string(),
            prediction: -0.02,
            confidence: 0.75,
            direction: "DOWN".to_string(),
            cached: true,
        };

        let json = serde_json::to_string(&resp).unwrap();
        assert!(json.contains("SYMBOL-B"));
        assert!(json.contains("DOWN"));
        assert!(json.contains("true"));
    }

    #[test]
    fn test_predict_response_deserialization() {
        let json = r#"{
            "symbol": "SYMBOL-A",
            "prediction": 0.03,
            "confidence": 0.9,
            "direction": "UP",
            "cached": false
        }"#;

        let resp: PredictResponse = serde_json::from_str(json).unwrap();
        assert_eq!(resp.symbol, "SYMBOL-A");
        assert_eq!(resp.prediction, 0.03);
        assert_eq!(resp.confidence, 0.9);
    }

    #[test]
    fn test_predict_request_empty_features() {
        let req = PredictRequest {
            symbol: "SYMBOL-A".to_string(),
            features: vec![],
        };

        assert!(req.features.is_empty());
    }

    #[test]
    fn test_predict_request_many_features() {
        let features: Vec<f64> = (0..100).map(|i| i as f64).collect();
        let req = PredictRequest {
            symbol: "SYMBOL-A".to_string(),
            features: features.clone(),
        };

        assert_eq!(req.features.len(), 100);
        assert_eq!(req.features[0], 0.0);
        assert_eq!(req.features[99], 99.0);
    }
}
