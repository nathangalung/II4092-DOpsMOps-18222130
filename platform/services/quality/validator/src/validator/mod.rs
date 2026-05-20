//! Validator components

use simd_json::prelude::{ValueAsScalar, ValueObjectAccess};

pub mod bounds;
pub mod dedup;
pub mod schema;

pub use bounds::BoundsChecker;
pub use dedup::DedupFilter;
pub use schema::SchemaValidator;

#[cfg(test)]
mod tests;

use anyhow::Result;

/// Combined validator
pub struct Validator {
    schema: SchemaValidator,
    dedup: DedupFilter,
    bounds: BoundsChecker,
}

impl Validator {
    pub fn new(schema: SchemaValidator, dedup: DedupFilter, bounds: BoundsChecker) -> Self {
        Self {
            schema,
            dedup,
            bounds,
        }
    }

    /// Validate record: schema, dedup, bounds
    pub fn validate(&self, data: &mut [u8]) -> Result<bool> {
        // Parse JSON
        let v: simd_json::OwnedValue = simd_json::to_owned_value(data)?;

        // Check schema
        if !self.schema.validate(&v) {
            return Ok(false);
        }

        // Check dedup
        let key = self.extract_key(&v)?;
        if !self.dedup.check(&key) {
            return Ok(false);
        }

        // Check bounds
        if !self.bounds.check(&v) {
            return Ok(false);
        }

        Ok(true)
    }

    fn extract_key(&self, v: &simd_json::OwnedValue) -> Result<String> {
        let symbol = v.get("symbol").and_then(|s| s.as_str()).unwrap_or("");
        let ts = v.get("timestamp").and_then(|t| t.as_str()).unwrap_or("0");
        Ok(format!("{}:{}", symbol, ts))
    }
}
