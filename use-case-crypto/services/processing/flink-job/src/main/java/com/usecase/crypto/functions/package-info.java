/**
 * Crypto-market microstructure feature functions.
 *
 * These {@link org.apache.flink.streaming.api.functions.KeyedProcessFunction}
 * implementations carry domain semantics specific to tradable markets with
 * sub-second trade streams and L2 orderbook update streams.
 *
 * They are loaded at runtime by the platform-generic
 * {@code com.pipeline.StreamJob} via reflection; the class names are
 * declared in the use-case-crypto ConfigMap under
 * {@code STREAM_TRADES_FUNCTION} and {@code STREAM_ORDERBOOK_FUNCTION}.
 *
 * ADR-013 — platform/ remains domain-agnostic; market-microstructure
 * feature logic lives in the use-case tree.
 */
package com.usecase.crypto.functions;
