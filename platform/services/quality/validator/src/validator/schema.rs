//! JSON Schema validation

use anyhow::Result;
use jsonschema::Validator;

pub struct SchemaValidator {
    schema: Validator,
}

impl SchemaValidator {
    pub fn new(schema_json: &str) -> Result<Self> {
        let schema: serde_json::Value = serde_json::from_str(schema_json)?;
        let compiled = Validator::new(&schema)?;
        Ok(Self { schema: compiled })
    }

    /// Validate against schema
    pub fn validate(&self, value: &simd_json::OwnedValue) -> bool {
        // Convert to serde_json for schema validation
        let json_str = simd_json::to_string(value).unwrap_or_default();
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&json_str) {
            self.schema.is_valid(&v)
        } else {
            false
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_schema_valid_record() {
        let schema_json = r#"{
            "type": "object",
            "required": ["symbol", "timestamp", "value"],
            "properties": {
                "symbol": {"type": "string"},
                "timestamp": {"type": "string"},
                "value": {"type": "number"}
            }
        }"#;

        let validator = SchemaValidator::new(schema_json).unwrap();

        let value = simd_json::json!({
            "symbol": "SYMBOL-A",
            "timestamp": "2025-01-13T12:00:00Z",
            "value": 100.0
        });

        assert!(validator.validate(&value));
    }

    #[test]
    fn test_schema_missing_required_field() {
        let schema_json = r#"{
            "type": "object",
            "required": ["symbol", "timestamp"],
            "properties": {
                "symbol": {"type": "string"},
                "timestamp": {"type": "string"}
            }
        }"#;

        let validator = SchemaValidator::new(schema_json).unwrap();

        let value = simd_json::json!({
            "symbol": "SYMBOL-A"
        });

        assert!(!validator.validate(&value));
    }

    #[test]
    fn test_schema_wrong_type() {
        let schema_json = r#"{
            "type": "object",
            "required": ["timestamp"],
            "properties": {
                "timestamp": {"type": "string"}
            }
        }"#;

        let validator = SchemaValidator::new(schema_json).unwrap();

        let value = simd_json::json!({
            "timestamp": 1234567890
        });

        assert!(!validator.validate(&value));
    }

    #[test]
    fn test_schema_extra_fields_allowed() {
        let schema_json = r#"{
            "type": "object",
            "required": ["symbol"],
            "properties": {
                "symbol": {"type": "string"}
            }
        }"#;

        let validator = SchemaValidator::new(schema_json).unwrap();

        let value = simd_json::json!({
            "symbol": "SYMBOL-A",
            "extra_field": "allowed"
        });

        assert!(validator.validate(&value));
    }

    #[test]
    fn test_schema_invalid_json() {
        let result = SchemaValidator::new("not json");
        assert!(result.is_err());
    }

    #[test]
    fn test_schema_empty_object() {
        let schema_json = r#"{
            "type": "object",
            "properties": {}
        }"#;

        let validator = SchemaValidator::new(schema_json).unwrap();
        let value = simd_json::json!({});
        assert!(validator.validate(&value));
    }
}
