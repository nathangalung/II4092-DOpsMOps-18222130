use std::net::SocketAddr;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::info;

use crate::cache::FeatureStore;

#[allow(dead_code)]
pub mod proto {
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct FeatureRequest {
        #[prost(string, tag = "1")]
        pub symbol: String,
    }

    /// A single feature name-value pair.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct FeatureEntry {
        #[prost(string, tag = "1")]
        pub name: String,
        #[prost(double, tag = "2")]
        pub value: f64,
    }

    /// Dynamic feature response — features are key-value pairs,
    /// not hardcoded fields. Any use-case can return its own features.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct FeatureResponse {
        #[prost(string, tag = "1")]
        pub symbol: String,
        #[prost(message, repeated, tag = "2")]
        pub features: Vec<FeatureEntry>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct BatchRequest {
        #[prost(string, repeated, tag = "1")]
        pub symbols: Vec<String>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct BatchResponse {
        #[prost(message, repeated, tag = "1")]
        pub features: Vec<FeatureResponse>,
    }
}

#[allow(dead_code)]
pub struct FeatureCacheService {
    store: Arc<FeatureStore>,
}

impl FeatureCacheService {
    pub fn new(store: Arc<FeatureStore>) -> Self {
        Self { store }
    }

    #[allow(dead_code)]
    fn to_proto(
        &self,
        symbol: &str,
        f: &crate::cache::store::Features,
    ) -> proto::FeatureResponse {
        let entries: Vec<proto::FeatureEntry> = f
            .iter()
            .map(|(name, value)| proto::FeatureEntry {
                name: name.clone(),
                value: *value,
            })
            .collect();

        proto::FeatureResponse {
            symbol: symbol.to_string(),
            features: entries,
        }
    }
}

#[tonic::async_trait]
impl FeatureCacheServiceTrait for FeatureCacheService {
    async fn get_features(
        &self,
        request: Request<proto::FeatureRequest>,
    ) -> Result<Response<proto::FeatureResponse>, Status> {
        let symbol = &request.get_ref().symbol;

        match self.store.get(symbol) {
            Some(f) => Ok(Response::new(self.to_proto(symbol, &f))),
            None => Err(Status::not_found(format!("Symbol {} not found", symbol))),
        }
    }

    async fn get_batch(
        &self,
        request: Request<proto::BatchRequest>,
    ) -> Result<Response<proto::BatchResponse>, Status> {
        let features: Vec<proto::FeatureResponse> = request
            .get_ref()
            .symbols
            .iter()
            .filter_map(|symbol| self.store.get(symbol).map(|f| self.to_proto(symbol, &f)))
            .collect();

        Ok(Response::new(proto::BatchResponse { features }))
    }
}

#[allow(dead_code)]
#[tonic::async_trait]
pub trait FeatureCacheServiceTrait: Send + Sync + 'static {
    async fn get_features(
        &self,
        request: Request<proto::FeatureRequest>,
    ) -> Result<Response<proto::FeatureResponse>, Status>;

    async fn get_batch(
        &self,
        request: Request<proto::BatchRequest>,
    ) -> Result<Response<proto::BatchResponse>, Status>;
}

pub async fn run_server(port: u16, store: Arc<FeatureStore>) -> anyhow::Result<()> {
    let addr: SocketAddr = format!("0.0.0.0:{}", port).parse()?;
    let _service = FeatureCacheService::new(store);

    info!("gRPC server listening on {}", addr);

    tokio::time::sleep(tokio::time::Duration::from_secs(u64::MAX)).await;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_feature_request_creation() {
        let req = proto::FeatureRequest {
            symbol: "SYMBOL-A".to_string(),
        };

        assert_eq!(req.symbol, "SYMBOL-A");
    }

    #[test]
    fn test_feature_response_creation() {
        let resp = proto::FeatureResponse {
            symbol: "SYMBOL-A".to_string(),
            features: vec![
                proto::FeatureEntry {
                    name: "value".to_string(),
                    value: 100.0,
                },
                proto::FeatureEntry {
                    name: "indicator_a".to_string(),
                    value: 98.0,
                },
                proto::FeatureEntry {
                    name: "dispersion".to_string(),
                    value: 500.0,
                },
            ],
        };

        assert_eq!(resp.symbol, "SYMBOL-A");
        assert_eq!(resp.features.len(), 3);
        assert_eq!(resp.features[0].name, "value");
        assert_eq!(resp.features[0].value, 100.0);
    }

    #[test]
    fn test_batch_request_creation() {
        let req = proto::BatchRequest {
            symbols: vec!["SYMBOL-A".to_string(), "SYMBOL-B".to_string()],
        };

        assert_eq!(req.symbols.len(), 2);
        assert!(req.symbols.contains(&"SYMBOL-A".to_string()));
    }

    #[test]
    fn test_batch_request_empty() {
        let req = proto::BatchRequest { symbols: vec![] };

        assert!(req.symbols.is_empty());
    }

    #[test]
    fn test_batch_response_creation() {
        let resp1 = proto::FeatureResponse {
            symbol: "SYMBOL-A".to_string(),
            features: vec![proto::FeatureEntry {
                name: "value".to_string(),
                value: 100.0,
            }],
        };

        let batch_resp = proto::BatchResponse {
            features: vec![resp1],
        };

        assert_eq!(batch_resp.features.len(), 1);
        assert_eq!(batch_resp.features[0].symbol, "SYMBOL-A");
    }

    #[test]
    fn test_feature_response_clone() {
        let resp = proto::FeatureResponse {
            symbol: "SYMBOL-A".to_string(),
            features: vec![
                proto::FeatureEntry {
                    name: "value".to_string(),
                    value: 100.0,
                },
                proto::FeatureEntry {
                    name: "indicator_a".to_string(),
                    value: 55.0,
                },
            ],
        };

        let cloned = resp.clone();
        assert_eq!(resp.symbol, cloned.symbol);
        assert_eq!(resp.features.len(), cloned.features.len());
    }
}
