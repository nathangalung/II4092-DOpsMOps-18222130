//! Coinbase WebSocket parser.
//!
//! Implements `websocket_collector::collectors::generic::MessageParser` for
//! the Coinbase Exchange feed channel schemas:
//!   - `ticker`                — best bid/ask + 24h stats, routed to primary topic
//!   - `match` / `last_match`  — executed trades, routed to trades topic
//!   - `l2update`              — L2 orderbook deltas, routed to orderbook topic
//!
//! Secondary (per-message-type) topic routing is driven by env vars so the
//! deployment ConfigMap stays the single source of truth:
//!   COINBASE_TRADES_TOPIC     (optional, defaults to the producer's base topic)
//!   COINBASE_ORDERBOOK_TOPIC  (optional, defaults to the producer's base topic)

use std::collections::BTreeMap;

use chrono::DateTime;
use simd_json::prelude::{ValueAsArray, ValueAsScalar, ValueObjectAccess};
use websocket_collector::collectors::{generic::MessageParser, Record};

pub struct CoinbaseParser {
    trades_topic: Option<String>,
    orderbook_topic: Option<String>,
}

impl CoinbaseParser {
    pub fn from_env() -> Self {
        Self {
            trades_topic: non_empty(std::env::var("COINBASE_TRADES_TOPIC").ok()),
            orderbook_topic: non_empty(std::env::var("COINBASE_ORDERBOOK_TOPIC").ok()),
        }
    }

    fn parse_ticker(&self, v: &simd_json::OwnedValue, source: &str) -> Option<Record> {
        let symbol = v.get("product_id")?.as_str()?.to_string();
        let price: f64 = v.get("price")?.as_str()?.parse().ok()?;
        let ts_str = v.get("time")?.as_str()?;
        let ts = DateTime::parse_from_rfc3339(ts_str).ok()?;

        let mut values = BTreeMap::new();
        values.insert("price".into(), price);
        insert_str_f64(&mut values, v, "best_bid", "bid");
        insert_str_f64(&mut values, v, "best_ask", "ask");
        insert_str_f64(&mut values, v, "volume_24h", "volume_24h");
        insert_str_f64(&mut values, v, "open_24h", "open_24h");
        insert_str_f64(&mut values, v, "high_24h", "high_24h");
        insert_str_f64(&mut values, v, "low_24h", "low_24h");
        insert_str_f64(&mut values, v, "last_size", "last_size");

        Some(Record {
            symbol,
            timestamp: ts.timestamp(),
            source: source.to_string(),
            target_topic: None,
            values,
        })
    }

    fn parse_match(&self, v: &simd_json::OwnedValue, source: &str) -> Option<Record> {
        let symbol = v.get("product_id")?.as_str()?.to_string();
        let price: f64 = v.get("price")?.as_str()?.parse().ok()?;
        let size: f64 = v.get("size")?.as_str()?.parse().ok()?;
        let side = v.get("side")?.as_str()?;
        let ts_str = v.get("time")?.as_str()?;
        let ts = DateTime::parse_from_rfc3339(ts_str).ok()?;
        let trade_id = v.get("trade_id")?.as_u64()? as f64;

        let mut values = BTreeMap::new();
        values.insert("price".into(), price);
        values.insert("size".into(), size);
        values.insert("trade_id".into(), trade_id);
        values.insert("side".into(), if side == "buy" { 1.0 } else { -1.0 });

        Some(Record {
            symbol,
            timestamp: ts.timestamp(),
            source: format!("{source}_trade"),
            target_topic: self.trades_topic.clone(),
            values,
        })
    }

    fn parse_l2update(&self, v: &simd_json::OwnedValue, source: &str) -> Option<Record> {
        let symbol = v.get("product_id")?.as_str()?.to_string();
        let ts_str = v.get("time")?.as_str()?;
        let ts = DateTime::parse_from_rfc3339(ts_str).ok()?;
        let changes = v.get("changes")?.as_array()?;

        let mut bid_count = 0.0_f64;
        let mut ask_count = 0.0_f64;
        let mut best_bid = 0.0_f64;
        let mut best_ask = f64::MAX;

        for change in changes {
            let arr: &[simd_json::OwnedValue] = match change.as_array() {
                Some(a) => a,
                None => continue,
            };
            if arr.len() < 3 {
                continue;
            }
            let side = arr[0].as_str().unwrap_or("");
            let price: f64 = arr[1].as_str().and_then(|s| s.parse().ok()).unwrap_or(0.0);
            let _size: f64 = arr[2].as_str().and_then(|s| s.parse().ok()).unwrap_or(0.0);
            match side {
                "buy" => {
                    bid_count += 1.0;
                    if price > best_bid {
                        best_bid = price;
                    }
                }
                "sell" => {
                    ask_count += 1.0;
                    if price < best_ask {
                        best_ask = price;
                    }
                }
                _ => {}
            }
        }

        let mut values = BTreeMap::new();
        values.insert("bid_changes".into(), bid_count);
        values.insert("ask_changes".into(), ask_count);
        if best_bid > 0.0 {
            values.insert("best_bid".into(), best_bid);
        }
        if best_ask < f64::MAX {
            values.insert("best_ask".into(), best_ask);
        }

        Some(Record {
            symbol,
            timestamp: ts.timestamp(),
            source: format!("{source}_orderbook"),
            target_topic: self.orderbook_topic.clone(),
            values,
        })
    }
}

impl MessageParser for CoinbaseParser {
    fn parse(&self, data: &mut [u8], source: &str) -> Option<Record> {
        let v: simd_json::OwnedValue = simd_json::to_owned_value(data).ok()?;
        match v.get("type")?.as_str()? {
            "ticker" => self.parse_ticker(&v, source),
            "match" | "last_match" => self.parse_match(&v, source),
            "l2update" => self.parse_l2update(&v, source),
            _ => None,
        }
    }
}

fn insert_str_f64(
    values: &mut BTreeMap<String, f64>,
    v: &simd_json::OwnedValue,
    json_key: &str,
    record_key: &str,
) {
    if let Some(n) = v
        .get(json_key)
        .and_then(|n| n.as_str())
        .and_then(|s| s.parse::<f64>().ok())
    {
        values.insert(record_key.into(), n);
    }
}

fn non_empty(s: Option<String>) -> Option<String> {
    s.filter(|v| !v.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parser(trades: Option<&str>, orderbook: Option<&str>) -> CoinbaseParser {
        CoinbaseParser {
            trades_topic: trades.map(|s| s.to_string()),
            orderbook_topic: orderbook.map(|s| s.to_string()),
        }
    }

    #[test]
    fn test_parse_ticker() {
        let p = parser(None, None);
        let mut data = br#"{
            "type":"ticker",
            "product_id":"BTC-USD",
            "price":"50000.12",
            "best_bid":"50000.00",
            "best_ask":"50000.24",
            "time":"2026-01-01T00:00:00.000Z"
        }"#
        .to_vec();

        let r = p.parse(&mut data, "coinbase").unwrap();
        assert_eq!(r.symbol, "BTC-USD");
        assert_eq!(r.source, "coinbase");
        assert_eq!(r.values["price"], 50000.12);
        assert_eq!(r.values["bid"], 50000.00);
        assert_eq!(r.values["ask"], 50000.24);
        assert!(r.target_topic.is_none());
    }

    #[test]
    fn test_parse_match_routes_to_trades_topic() {
        let p = parser(Some("crypto-trades"), None);
        let mut data = br#"{
            "type":"match",
            "product_id":"BTC-USD",
            "price":"50000.00",
            "size":"0.01",
            "side":"buy",
            "trade_id":12345,
            "time":"2026-01-01T00:00:00.000Z"
        }"#
        .to_vec();

        let r = p.parse(&mut data, "coinbase").unwrap();
        assert_eq!(r.symbol, "BTC-USD");
        assert_eq!(r.source, "coinbase_trade");
        assert_eq!(r.values["price"], 50000.00);
        assert_eq!(r.values["size"], 0.01);
        assert_eq!(r.values["side"], 1.0);
        assert_eq!(r.target_topic.as_deref(), Some("crypto-trades"));
    }

    #[test]
    fn test_parse_l2update_routes_to_orderbook_topic() {
        let p = parser(None, Some("crypto-orderbook"));
        let mut data = br#"{
            "type":"l2update",
            "product_id":"BTC-USD",
            "time":"2026-01-01T00:00:00.000Z",
            "changes":[["buy","49999.50","0.1"],["sell","50000.50","0.2"]]
        }"#
        .to_vec();

        let r = p.parse(&mut data, "coinbase").unwrap();
        assert_eq!(r.symbol, "BTC-USD");
        assert_eq!(r.source, "coinbase_orderbook");
        assert_eq!(r.values["bid_changes"], 1.0);
        assert_eq!(r.values["ask_changes"], 1.0);
        assert_eq!(r.values["best_bid"], 49999.50);
        assert_eq!(r.values["best_ask"], 50000.50);
        assert_eq!(r.target_topic.as_deref(), Some("crypto-orderbook"));
    }

    #[test]
    fn test_unknown_type_ignored() {
        let p = parser(None, None);
        let mut data = br#"{"type":"heartbeat","product_id":"BTC-USD"}"#.to_vec();
        assert!(p.parse(&mut data, "coinbase").is_none());
    }

    #[test]
    fn test_missing_type_ignored() {
        let p = parser(None, None);
        let mut data = br#"{"product_id":"BTC-USD"}"#.to_vec();
        assert!(p.parse(&mut data, "coinbase").is_none());
    }
}
