use std::net::SocketAddr;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::info;

use crate::engine::FeatureEngine;

#[allow(dead_code)]
pub mod proto {
    use std::collections::HashMap;

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct FeatureRequest {
        #[prost(string, tag = "1")]
        pub symbol: String,
    }

    /// Generic feature response — dynamic key-value pairs instead of
    /// hardcoded fields. Use-cases define which indicators appear via config.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct FeatureResponse {
        #[prost(string, tag = "1")]
        pub symbol: String,
        #[prost(map = "string, double", tag = "2")]
        pub features: HashMap<String, f64>,
    }
}

#[allow(dead_code)]
pub struct FeatureService {
    engine: Arc<FeatureEngine>,
}

impl FeatureService {
    pub fn new(engine: Arc<FeatureEngine>) -> Self {
        Self { engine }
    }
}

#[tonic::async_trait]
impl FeatureServiceTrait for FeatureService {
    async fn get_features(
        &self,
        request: Request<proto::FeatureRequest>,
    ) -> Result<Response<proto::FeatureResponse>, Status> {
        let symbol = &request.get_ref().symbol;

        match self.engine.get_features(symbol) {
            Some(features) => Ok(Response::new(proto::FeatureResponse {
                symbol: symbol.clone(),
                features: features.into_iter().collect(),
            })),
            None => Err(Status::not_found(format!("Symbol {} not found", symbol))),
        }
    }
}

#[allow(dead_code)]
#[tonic::async_trait]
pub trait FeatureServiceTrait: Send + Sync + 'static {
    async fn get_features(
        &self,
        request: Request<proto::FeatureRequest>,
    ) -> Result<Response<proto::FeatureResponse>, Status>;
}

pub async fn run_server(port: u16, engine: Arc<FeatureEngine>) -> anyhow::Result<()> {
    let addr: SocketAddr = format!("0.0.0.0:{}", port).parse()?;
    let _service = FeatureService::new(engine);

    info!("gRPC server listening on {}", addr);

    tokio::time::sleep(tokio::time::Duration::from_secs(u64::MAX)).await;

    Ok(())
}
