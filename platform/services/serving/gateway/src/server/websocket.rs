use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tracing::{debug, error, info};

use crate::cache::CacheLayer;

pub async fn run_ws_server(port: u16, cache: Arc<CacheLayer>) -> anyhow::Result<()> {
    let listener = TcpListener::bind(format!("0.0.0.0:{}", port)).await?;
    info!("WebSocket server listening on port {}", port);

    loop {
        match listener.accept().await {
            Ok((mut socket, addr)) => {
                debug!("New connection from {}", addr);
                let cache_clone = cache.clone();

                tokio::spawn(async move {
                    let mut buf = [0u8; 4096];

                    loop {
                        match socket.read(&mut buf).await {
                            Ok(0) => break,
                            Ok(n) => {
                                let msg = String::from_utf8_lossy(&buf[..n]);

                                if let Some(symbol) = parse_subscribe_request(&msg)
                                    && let Some(data) =
                                        cache_clone.get(&format!("features:{}", symbol)).await
                                {
                                    let response =
                                        format!("{{\"type\":\"features\",\"data\":{}}}", data);
                                    let _ = socket.write_all(response.as_bytes()).await;
                                }
                            }
                            Err(e) => {
                                error!("Socket error: {}", e);
                                break;
                            }
                        }
                    }
                });
            }
            Err(e) => error!("Accept error: {}", e),
        }
    }
}

fn parse_subscribe_request(msg: &str) -> Option<String> {
    if let Ok(json) = serde_json::from_str::<serde_json::Value>(msg)
        && json.get("type").and_then(|v| v.as_str()) == Some("subscribe")
    {
        return json.get("symbol").and_then(|v| v.as_str()).map(String::from);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_subscribe_request_valid() {
        let msg = r#"{"type": "subscribe", "symbol": "SYMBOL-A"}"#;
        let result = parse_subscribe_request(msg);
        assert_eq!(result, Some("SYMBOL-A".to_string()));
    }

    #[test]
    fn test_parse_subscribe_request_wrong_type() {
        let msg = r#"{"type": "unsubscribe", "symbol": "SYMBOL-A"}"#;
        let result = parse_subscribe_request(msg);
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_subscribe_request_missing_symbol() {
        let msg = r#"{"type": "subscribe"}"#;
        let result = parse_subscribe_request(msg);
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_subscribe_request_invalid_json() {
        let msg = "not json";
        let result = parse_subscribe_request(msg);
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_subscribe_request_empty() {
        let result = parse_subscribe_request("");
        assert_eq!(result, None);
    }

    #[test]
    fn test_parse_subscribe_request_different_symbols() {
        let symbols = vec!["SYMBOL-A", "SYMBOL-B", "SYMBOL-C"];
        for symbol in symbols {
            let msg = format!(r#"{{"type": "subscribe", "symbol": "{}"}}"#, symbol);
            let result = parse_subscribe_request(&msg);
            assert_eq!(result, Some(symbol.to_string()));
        }
    }
}
