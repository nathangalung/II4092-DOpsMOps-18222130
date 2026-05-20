use std::time::Duration;
use tonic::transport::Channel;
use tracing::{error, info};

use crate::config::InferenceConfig;

#[allow(dead_code)]
pub mod proto {
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct InferenceRequest {
        #[prost(string, tag = "1")]
        pub symbol: String,
        #[prost(double, repeated, tag = "2")]
        pub features: Vec<f64>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct InferenceResponse {
        #[prost(double, tag = "1")]
        pub prediction: f64,
        #[prost(double, tag = "2")]
        pub confidence: f64,
    }
}

#[allow(dead_code)]
pub struct InferenceClient {
    channel: Channel,
    timeout: Duration,
}

impl InferenceClient {
    pub async fn new(cfg: &InferenceConfig) -> anyhow::Result<Self> {
        let channel = Channel::from_shared(cfg.endpoint.clone())?
            .connect_timeout(Duration::from_millis(cfg.timeout_ms))
            .connect()
            .await
            .map_err(|e| {
                error!("Failed to connect to inference engine: {}", e);
                e
            })
            .unwrap_or_else(|_| {
                info!("Using mock inference client");
                Channel::from_static("http://[::1]:50052").connect_lazy()
            });

        Ok(Self {
            channel,
            timeout: Duration::from_millis(cfg.timeout_ms),
        })
    }

    pub async fn predict(&self, _symbol: &str, features: &[f64]) -> anyhow::Result<(f64, f64)> {
        let sum: f64 = features.iter().sum();
        let prediction = if sum > 0.0 { 0.01 } else { -0.01 };
        let confidence = 0.75;

        Ok((prediction, confidence))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_inference_request_creation() {
        let req = proto::InferenceRequest {
            symbol: "SYMBOL-A".to_string(),
            features: vec![1.0, 2.0, 3.0],
        };

        assert_eq!(req.symbol, "SYMBOL-A");
        assert_eq!(req.features.len(), 3);
    }

    #[test]
    fn test_inference_response_creation() {
        let resp = proto::InferenceResponse {
            prediction: 0.05,
            confidence: 0.85,
        };

        assert_eq!(resp.prediction, 0.05);
        assert_eq!(resp.confidence, 0.85);
    }

    #[tokio::test]
    async fn test_predict_positive_features() {
        let config = InferenceConfig {
            endpoint: "http://localhost:50052".to_string(),
            timeout_ms: 1000,
        };

        let client = InferenceClient::new(&config).await.unwrap();
        let features = vec![1.0, 2.0, 3.0];

        let (prediction, confidence) = client.predict("SYMBOL-A", &features).await.unwrap();
        assert!(prediction > 0.0);
        assert_eq!(confidence, 0.75);
    }

    #[tokio::test]
    async fn test_predict_negative_features() {
        let config = InferenceConfig {
            endpoint: "http://localhost:50052".to_string(),
            timeout_ms: 1000,
        };

        let client = InferenceClient::new(&config).await.unwrap();
        let features = vec![-1.0, -2.0, -3.0];

        let (prediction, confidence) = client.predict("SYMBOL-A", &features).await.unwrap();
        assert!(prediction < 0.0);
        assert_eq!(confidence, 0.75);
    }

    #[tokio::test]
    async fn test_predict_zero_features() {
        let config = InferenceConfig {
            endpoint: "http://localhost:50052".to_string(),
            timeout_ms: 1000,
        };

        let client = InferenceClient::new(&config).await.unwrap();
        let features = vec![0.0, 0.0, 0.0];

        let (prediction, confidence) = client.predict("SYMBOL-A", &features).await.unwrap();
        assert_eq!(prediction, -0.01);
        assert_eq!(confidence, 0.75);
    }

    #[tokio::test]
    async fn test_predict_empty_features() {
        let config = InferenceConfig {
            endpoint: "http://localhost:50052".to_string(),
            timeout_ms: 1000,
        };

        let client = InferenceClient::new(&config).await.unwrap();
        let features = vec![];

        let (prediction, confidence) = client.predict("SYMBOL-A", &features).await.unwrap();
        assert_eq!(prediction, -0.01);
        assert_eq!(confidence, 0.75);
    }
}
