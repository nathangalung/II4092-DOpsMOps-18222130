package com.pipeline.sinks;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for RedisSink (the Valkey/RESP feature sink).
 *
 * These verify object construction and serializability only — the sink is
 * lazily connected (the RedisClient is created in createWriter, not the
 * constructor), so building a sink against an unreachable host does NOT throw.
 * Integration tests against a real Valkey would require Testcontainers.
 *
 * Constructor contract: RedisSink(host, port, password, keyPrefix).
 *   - password may be null/empty (no-auth dev Valkey).
 *   - keyPrefix may be null/empty (falls back to the legacy bare "features:");
 *     StreamJob always supplies a per-stream namespaced prefix in production.
 */
public class RedisSinkTest {

    private static final String PW = "";                 // no-auth dev default
    private static final String PREFIX = "features:test:";

    @Test
    @DisplayName("Should create RedisSink with valid parameters")
    public void testCreateRedisSink() {
        RedisSink sink = new RedisSink("localhost", 6379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should construct with null host (connection is lazy, no eager throw)")
    public void testNullHost() {
        RedisSink sink = new RedisSink(null, 6379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with custom port")
    public void testCustomPort() {
        RedisSink sink = new RedisSink("localhost", 16379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with IP address")
    public void testIpAddress() {
        RedisSink sink = new RedisSink("192.168.1.100", 6379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle negative port")
    public void testNegativePort() {
        RedisSink sink = new RedisSink("localhost", -1, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle zero port")
    public void testZeroPort() {
        RedisSink sink = new RedisSink("localhost", 0, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle very large port number")
    public void testLargePort() {
        RedisSink sink = new RedisSink("localhost", 65535, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with hostname")
    public void testHostname() {
        RedisSink sink = new RedisSink("redis.example.com", 6379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should tolerate null password (no-auth Valkey)")
    public void testNullPassword() {
        RedisSink sink = new RedisSink("localhost", 6379, null, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should tolerate null key prefix (falls back to legacy bare prefix)")
    public void testNullKeyPrefix() {
        RedisSink sink = new RedisSink("localhost", 6379, PW, null);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should tolerate empty key prefix (falls back to legacy bare prefix)")
    public void testEmptyKeyPrefix() {
        RedisSink sink = new RedisSink("localhost", 6379, PW, "");
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should be serializable")
    public void testSerializable() {
        RedisSink sink = new RedisSink("localhost", 6379, PW, PREFIX);
        assertTrue(sink instanceof java.io.Serializable);
    }

    @Test
    @DisplayName("Should handle empty host string")
    public void testEmptyHost() {
        RedisSink sink = new RedisSink("", 6379, PW, PREFIX);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create multiple sinks with same parameters")
    public void testMultipleSinks() {
        RedisSink sink1 = new RedisSink("localhost", 6379, PW, PREFIX);
        RedisSink sink2 = new RedisSink("localhost", 6379, PW, PREFIX);

        assertNotNull(sink1);
        assertNotNull(sink2);
        assertNotSame(sink1, sink2);
    }

    @Test
    @DisplayName("Should create sinks with different per-stream key prefixes")
    public void testDifferentKeyPrefixes() {
        RedisSink trades = new RedisSink("localhost", 6379, PW, "features:trades:");
        RedisSink orderbook = new RedisSink("localhost", 6379, PW, "features:orderbook:");

        assertNotNull(trades);
        assertNotNull(orderbook);
        assertNotSame(trades, orderbook);
    }

    @Test
    @DisplayName("Should create sinks with different ports")
    public void testDifferentPorts() {
        RedisSink sink1 = new RedisSink("localhost", 6379, PW, PREFIX);
        RedisSink sink2 = new RedisSink("localhost", 6380, PW, PREFIX);

        assertNotNull(sink1);
        assertNotNull(sink2);
    }
}
