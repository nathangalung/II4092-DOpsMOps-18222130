//! Generic WebSocket collector — platform-agnostic connection / dispatch loop.
//!
//! The collector holds a `MessageParser` implementation which translates raw
//! WebSocket payloads into the platform `Record` structure. Platform ships
//! `DefaultTickerParser` (multi-convention ticker extractor); use-case crates
//! provide their own parsers for exchange-specific schemas.

use std::collections::BTreeMap;

use super::{Collector, Record};
use crate::config::SourceConfig;
use anyhow::Result;
use async_trait::async_trait;
use chrono::Utc;
use futures::{SinkExt, StreamExt};
use simd_json::prelude::{ValueAsScalar, ValueObjectAccess};
use tokio::sync::mpsc;
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info};

/// Translates a raw WebSocket payload into a platform `Record`.
///
/// Use-case crates implement this to parse exchange-specific JSON schemas.
/// `source` is the logical source name (from `SourceConfig.name`) and must be
/// written into the resulting `Record.source`.
///
/// Returning `None` signals "ignore this frame" (heartbeats, subscription
/// acks, malformed payloads, etc.).
pub trait MessageParser: Send + Sync {
    fn parse(&self, data: &mut [u8], source: &str) -> Option<Record>;
}

/// Platform-default parser. Extracts common ticker fields using a multi-key
/// fallback strategy (`symbol`/`product_id`/`s`; `price`/`close`/`c`; etc.)
/// and emits a `Record` keyed into generic `value_1..value_5` slots.
///
/// Works against any feed whose top-level JSON has a recognizable symbol
/// field and at least one numeric price-like field.
pub struct DefaultTickerParser;

impl MessageParser for DefaultTickerParser {
    fn parse(&self, data: &mut [u8], source: &str) -> Option<Record> {
        let v: simd_json::OwnedValue = simd_json::to_owned_value(data).ok()?;

        let symbol = v
            .get("symbol")
            .or_else(|| v.get("product_id"))
            .or_else(|| v.get("s"))
            .and_then(|n| n.as_str())
            .map(|s| s.to_string())?;

        let mut values = BTreeMap::new();
        let field_patterns: &[(&[&str], &str)] = &[
            (&["value", "price", "close", "c"], "value_1"),
            (&["open", "open_24h", "o"], "value_2"),
            (&["high", "high_24h", "h"], "value_3"),
            (&["low", "low_24h", "l"], "value_4"),
            (&["volume", "volume_24h", "v"], "value_5"),
        ];

        for (patterns, key) in field_patterns {
            for &pattern in *patterns {
                if let Some(val) = v
                    .get(pattern)
                    .and_then(|n| n.as_str())
                    .and_then(|s| s.parse::<f64>().ok())
                {
                    values.insert(key.to_string(), val);
                    break;
                }
            }
        }

        if values.is_empty() {
            return None;
        }

        Some(Record {
            symbol,
            timestamp: Utc::now().timestamp_millis(),
            source: source.to_string(),
            target_topic: None,
            values,
        })
    }
}

/// WebSocket connection manager. Owns the connect / subscribe / reconnect
/// loop and delegates payload interpretation to `P: MessageParser`.
pub struct GenericCollector<P: MessageParser> {
    config: SourceConfig,
    tx: mpsc::Sender<Record>,
    parser: P,
}

impl<P: MessageParser> GenericCollector<P> {
    pub fn new(config: &SourceConfig, tx: mpsc::Sender<Record>, parser: P) -> Self {
        Self {
            config: config.clone(),
            tx,
            parser,
        }
    }
}

#[async_trait]
impl<P: MessageParser + 'static> Collector for GenericCollector<P> {
    async fn run(&self) -> Result<()> {
        loop {
            info!(
                "Connecting to WebSocket source: {} at {}",
                self.config.name, self.config.ws_url
            );

            match connect_async(&self.config.ws_url).await {
                Ok((mut ws, _)) => {
                    if let Some(ref subscribe_msg) = self.config.subscribe_msg {
                        let msg = if subscribe_msg.contains("{{SYMBOLS}}") {
                            let symbols_json = serde_json::to_string(&self.config.symbols)
                                .unwrap_or_else(|_| "[]".to_string());
                            subscribe_msg.replace("{{SYMBOLS}}", &symbols_json)
                        } else {
                            subscribe_msg.clone()
                        };

                        ws.send(Message::Text(msg)).await?;
                        info!(
                            "Subscribed to {} with symbols: {:?}",
                            self.config.name, self.config.symbols
                        );
                    }

                    while let Some(msg) = ws.next().await {
                        match msg {
                            Ok(Message::Text(text)) => {
                                let mut bytes = text.into_bytes();
                                if let Some(record) =
                                    self.parser.parse(&mut bytes, &self.config.name)
                                {
                                    debug!(
                                        "Received from {}: {} ({} values)",
                                        self.config.name,
                                        record.symbol,
                                        record.values.len()
                                    );
                                    if self.tx.send(record).await.is_err() {
                                        error!("Channel closed");
                                        return Ok(());
                                    }
                                }
                            }
                            Ok(Message::Close(_)) => {
                                info!("WebSocket closed for {}", self.config.name);
                                break;
                            }
                            Err(e) => {
                                error!("WebSocket error for {}: {}", self.config.name, e);
                                break;
                            }
                            _ => {}
                        }
                    }
                }
                Err(e) => {
                    error!("Connection failed for {}: {}", self.config.name, e);
                }
            }

            tokio::time::sleep(tokio::time::Duration::from_secs(5)).await;
        }
    }

    fn source(&self) -> &str {
        &self.config.name
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_ticker_full_field_names() {
        let parser = DefaultTickerParser;
        let mut data = r#"{
            "symbol": "SYM1",
            "price": "100.50",
            "open": "98.00",
            "high": "102.00",
            "low": "97.00",
            "volume": "1234.56"
        }"#
        .to_string()
        .into_bytes();

        let record = parser.parse(&mut data, "test-source").unwrap();
        assert_eq!(record.symbol, "SYM1");
        assert_eq!(record.values["value_1"], 100.50);
        assert_eq!(record.values["value_2"], 98.00);
        assert_eq!(record.values["value_3"], 102.00);
        assert_eq!(record.values["value_4"], 97.00);
        assert_eq!(record.values["value_5"], 1234.56);
        assert_eq!(record.source, "test-source");
    }

    #[test]
    fn test_default_ticker_product_id_field() {
        let parser = DefaultTickerParser;
        let mut data = r#"{
            "product_id": "SYM1",
            "price": "100.50",
            "open_24h": "98.00",
            "high_24h": "102.00",
            "low_24h": "97.00",
            "volume_24h": "1234.56"
        }"#
        .to_string()
        .into_bytes();

        let record = parser.parse(&mut data, "test-source").unwrap();
        assert_eq!(record.symbol, "SYM1");
        assert_eq!(record.values["value_1"], 100.50);
        assert_eq!(record.source, "test-source");
    }

    #[test]
    fn test_default_ticker_short_field_names() {
        let parser = DefaultTickerParser;
        let mut data = r#"{
            "s": "SYM1",
            "c": "45000.00",
            "o": "44000.00",
            "h": "46000.00",
            "l": "43500.00",
            "v": "987.65"
        }"#
        .to_string()
        .into_bytes();

        let record = parser.parse(&mut data, "test-source").unwrap();
        assert_eq!(record.symbol, "SYM1");
        assert_eq!(record.values["value_1"], 45000.00);
        assert_eq!(record.values["value_5"], 987.65);
    }

    #[test]
    fn test_default_ticker_missing_numeric_fields() {
        let parser = DefaultTickerParser;
        let mut data = r#"{"symbol":"SYM1"}"#.to_string().into_bytes();
        assert!(parser.parse(&mut data, "test-source").is_none());
    }

    #[test]
    fn test_default_ticker_invalid_json() {
        let parser = DefaultTickerParser;
        let mut data = b"not json".to_vec();
        assert!(parser.parse(&mut data, "test-source").is_none());
    }

    #[test]
    fn test_default_ticker_invalid_numbers_partial() {
        let parser = DefaultTickerParser;
        let mut data = r#"{
            "symbol": "SYM1",
            "price": "not_a_number",
            "open": "98.00",
            "high": "102.00",
            "low": "97.00",
            "volume": "1234.56"
        }"#
        .to_string()
        .into_bytes();

        let record = parser.parse(&mut data, "test-source").unwrap();
        assert!(!record.values.contains_key("value_1"));
        assert_eq!(record.values["value_2"], 98.00);
    }

    #[test]
    fn test_collector_source_name() {
        let (tx, _rx) = mpsc::channel(10);
        let config = SourceConfig {
            enabled: true,
            name: "custom-source".to_string(),
            ws_url: "wss://test".to_string(),
            subscribe_msg: Some(r#"{"action":"subscribe"}"#.to_string()),
            symbols: vec![],
        };
        let collector = GenericCollector::new(&config, tx, DefaultTickerParser);
        assert_eq!(collector.source(), "custom-source");
    }
}
