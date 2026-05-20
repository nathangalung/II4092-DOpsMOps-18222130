use super::*;
use crate::config::BoundsConfig;

fn create_test_validator() -> Validator {
    let schema_json = r#"{
        "type": "object",
        "required": ["symbol", "timestamp", "value"],
        "properties": {
            "symbol": {"type": "string"},
            "timestamp": {"type": "string"},
            "value": {"type": "number"}
        }
    }"#;

    let schema = SchemaValidator::new(schema_json).unwrap();
    let dedup = DedupFilter::new(1000, 0.01);
    let bounds_cfg = BoundsConfig {
        range_check_columns: "value".to_string(),
        range_min: 0.0,
        range_max: 1_000_000.0,
        nonneg_columns: "count".to_string(),
    };
    let bounds = BoundsChecker::new(&bounds_cfg);

    Validator::new(schema, dedup, bounds)
}

#[test]
fn test_validate_valid_record() {
    let validator = create_test_validator();

    let mut data = r#"{
        "symbol": "SYMBOL-A",
        "timestamp": "2025-01-13T12:00:00Z",
        "value": 500.0,
        "count": 100.0
    }"#
    .to_string()
    .into_bytes();

    let result = validator.validate(&mut data).unwrap();
    assert!(result);
}

#[test]
fn test_validate_duplicate() {
    let validator = create_test_validator();

    let mut data = r#"{
        "symbol": "SYMBOL-A",
        "timestamp": "2025-01-13T12:00:00Z",
        "value": 500.0
    }"#
    .to_string()
    .into_bytes();

    assert!(validator.validate(&mut data).unwrap());

    let mut data2 = r#"{
        "symbol": "SYMBOL-A",
        "timestamp": "2025-01-13T12:00:00Z",
        "value": 500.0
    }"#
    .to_string()
    .into_bytes();

    assert!(!validator.validate(&mut data2).unwrap());
}

#[test]
fn test_validate_invalid_schema() {
    let validator = create_test_validator();

    let mut data = r#"{
        "symbol": "SYMBOL-A"
    }"#
    .to_string()
    .into_bytes();

    let result = validator.validate(&mut data).unwrap();
    assert!(!result);
}

#[test]
fn test_validate_out_of_bounds() {
    let validator = create_test_validator();

    let mut data = r#"{
        "symbol": "SYMBOL-A",
        "timestamp": "2025-01-13T12:00:00Z",
        "value": 2000000.0
    }"#
    .to_string()
    .into_bytes();

    let result = validator.validate(&mut data).unwrap();
    assert!(!result);
}

#[test]
fn test_validate_invalid_json() {
    let validator = create_test_validator();

    let mut data = b"not json".to_vec();
    let result = validator.validate(&mut data);
    assert!(result.is_err());
}
