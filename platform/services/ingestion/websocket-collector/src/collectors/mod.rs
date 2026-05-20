//! Collector traits and implementations

pub mod generic;

#[cfg(test)]
mod tests;

use std::collections::BTreeMap;

use anyhow::Result;
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

/// Generic data record from any WebSocket source.
/// Symbol and timestamp are required identifiers; all numeric values are
/// stored in the `values` map, keyed by configurable field names.
/// This allows any use-case to define its own schema.
///
/// JSON wire format is FLAT — values are promoted to top-level fields:
///
///   {"symbol":"X","timestamp":123,"source":"s","value":100,"volume":50}
///
/// This allows downstream services (validator, feature engine) to read fields
/// directly without nested "values" indirection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Record {
    pub symbol: String,
    pub timestamp: i64,
    pub source: String,
    #[serde(skip)]
    pub target_topic: Option<String>,
    #[serde(flatten)]
    pub values: BTreeMap<String, f64>,
}

/// Collector trait
#[async_trait]
pub trait Collector: Send + Sync {
    async fn run(&self) -> Result<()>;
    #[allow(dead_code)]
    fn source(&self) -> &str;
}
