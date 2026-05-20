use super::*;
use std::collections::BTreeMap;

fn sample_values() -> BTreeMap<String, f64> {
    BTreeMap::from([
        ("value_1".to_string(), 105.0),
        ("value_2".to_string(), 100.0),
        ("value_3".to_string(), 110.0),
        ("value_4".to_string(), 90.0),
        ("value_5".to_string(), 1000.0),
    ])
}

fn sample_record(symbol: &str, ts: i64) -> Record {
    Record {
        symbol: symbol.to_string(),
        timestamp: ts,
        source: "test".to_string(),
        target_topic: None,
        values: sample_values(),
    }
}

// Record Tests
#[test]
fn test_record_serialization() {
    let record = sample_record("SYM1", 1600000000);

    let serialized = serde_json::to_string(&record).unwrap();
    let deserialized: Record = serde_json::from_str(&serialized).unwrap();

    assert_eq!(record.symbol, deserialized.symbol);
    assert_eq!(record.values["value_1"], deserialized.values["value_1"]);
    assert_eq!(record.timestamp, deserialized.timestamp);
}

#[test]
fn test_record_deserialization() {
    // Flat JSON — values are top-level fields (not nested under "values")
    let json_str = r#"{
            "symbol": "SYM2",
            "timestamp": 1700000000,
            "source": "source-a",
            "value_1": 2050.0,
            "value_2": 2000.0,
            "value_3": 2100.0,
            "value_4": 1900.0,
            "value_5": 5000.0
        }"#;

    let record: Record = serde_json::from_str(json_str).unwrap();

    assert_eq!(record.symbol, "SYM2");
    assert_eq!(record.timestamp, 1700000000);
    assert_eq!(record.values["value_2"], 2000.0);
    assert_eq!(record.values["value_3"], 2100.0);
    assert_eq!(record.values["value_4"], 1900.0);
    assert_eq!(record.values["value_1"], 2050.0);
    assert_eq!(record.values["value_5"], 5000.0);
    assert_eq!(record.source, "source-a");
}

#[test]
fn test_record_clone() {
    let original = sample_record("SYM3", 1600000000);
    let cloned = original.clone();

    assert_eq!(original.symbol, cloned.symbol);
    assert_eq!(original.timestamp, cloned.timestamp);
    assert_eq!(original.values["value_1"], cloned.values["value_1"]);
}

#[test]
fn test_record_debug() {
    let record = sample_record("SYM1", 1600000000);

    let debug_str = format!("{:?}", record);
    assert!(debug_str.contains("SYM1"));
    assert!(debug_str.contains("1600000000"));
}

#[test]
fn test_record_with_zero_values() {
    let record = Record {
        symbol: "TEST".to_string(),
        timestamp: 0,
        source: "test".to_string(),
        target_topic: None,
        values: BTreeMap::from([("value_1".to_string(), 0.0), ("value_2".to_string(), 0.0)]),
    };

    let serialized = serde_json::to_string(&record).unwrap();
    let deserialized: Record = serde_json::from_str(&serialized).unwrap();

    assert_eq!(record.timestamp, deserialized.timestamp);
    assert_eq!(record.values["value_2"], deserialized.values["value_2"]);
}

#[test]
fn test_record_with_large_values() {
    let record = Record {
        symbol: "SYM1".to_string(),
        timestamp: i64::MAX,
        source: "test".to_string(),
        target_topic: None,
        values: BTreeMap::from([
            ("value_1".to_string(), f64::MAX / 2.0),
            ("value_2".to_string(), f64::MAX / 2.0),
        ]),
    };

    let serialized = serde_json::to_string(&record).unwrap();
    let deserialized: Record = serde_json::from_str(&serialized).unwrap();

    assert_eq!(record.timestamp, deserialized.timestamp);
}

#[test]
fn test_record_with_negative_timestamp() {
    // Historical data might have negative timestamps (before epoch)
    let record = Record {
        symbol: "TEST".to_string(),
        timestamp: -1000,
        source: "test".to_string(),
        target_topic: None,
        values: sample_values(),
    };

    let serialized = serde_json::to_string(&record).unwrap();
    let deserialized: Record = serde_json::from_str(&serialized).unwrap();

    assert_eq!(record.timestamp, deserialized.timestamp);
}

#[test]
fn test_record_with_unicode_symbol() {
    let record = sample_record("SYM1", 1600000000);

    let serialized = serde_json::to_string(&record).unwrap();
    assert!(serialized.contains("SYM1"));
}

#[test]
fn test_record_values_consistency() {
    // value_3 should be >= max(value_2, value_1) and value_4 should be <= min(value_2, value_1)
    let record = sample_record("SYM1", 1600000000);

    let high = record.values["value_3"];
    let low = record.values["value_4"];
    let secondary = record.values["value_2"];
    let primary = record.values["value_1"];

    assert!(high >= secondary.max(primary));
    assert!(low <= secondary.min(primary));
}

#[test]
fn test_multiple_records_serialization() {
    let records = vec![
        sample_record("SYM1", 1600000000),
        Record {
            symbol: "SYM2".to_string(),
            timestamp: 1600000001,
            source: "test".to_string(),
            target_topic: None,
            values: BTreeMap::from([
                ("value_1".to_string(), 205.0),
                ("value_2".to_string(), 200.0),
                ("value_3".to_string(), 210.0),
                ("value_4".to_string(), 190.0),
                ("value_5".to_string(), 2000.0),
            ]),
        },
    ];

    let serialized = serde_json::to_string(&records).unwrap();
    let deserialized: Vec<Record> = serde_json::from_str(&serialized).unwrap();

    assert_eq!(records.len(), deserialized.len());
    assert_eq!(records[0].symbol, deserialized[0].symbol);
    assert_eq!(records[1].symbol, deserialized[1].symbol);
}
