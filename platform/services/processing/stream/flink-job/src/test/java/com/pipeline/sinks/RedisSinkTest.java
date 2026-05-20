package com.pipeline.sinks;

import org.apache.flink.api.connector.sink2.SinkWriter;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for RedisSink.
 * Note: These tests verify object creation and serialization.
 * Integration tests with real Redis would require test containers.
 */
public class RedisSinkTest {

    @Test
    @DisplayName("Should create RedisSink with valid parameters")
    public void testCreateRedisSink() {
        RedisSink sink = new RedisSink("localhost", 6379);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle null host")
    public void testNullHost() {
        assertThrows(NullPointerException.class, () -> {
            RedisSink sink = new RedisSink(null, 6379);
        });
    }

    @Test
    @DisplayName("Should create sink with custom port")
    public void testCustomPort() {
        RedisSink sink = new RedisSink("localhost", 16379);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with IP address")
    public void testIpAddress() {
        RedisSink sink = new RedisSink("192.168.1.100", 6379);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle negative port")
    public void testNegativePort() {
        RedisSink sink = new RedisSink("localhost", -1);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle zero port")
    public void testZeroPort() {
        RedisSink sink = new RedisSink("localhost", 0);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle very large port number")
    public void testLargePort() {
        RedisSink sink = new RedisSink("localhost", 65535);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with hostname")
    public void testHostname() {
        RedisSink sink = new RedisSink("redis.example.com", 6379);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should be serializable")
    public void testSerializable() {
        RedisSink sink = new RedisSink("localhost", 6379);
        assertTrue(sink instanceof java.io.Serializable);
    }

    @Test
    @DisplayName("Should handle empty host string")
    public void testEmptyHost() {
        RedisSink sink = new RedisSink("", 6379);
        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create multiple sinks with same parameters")
    public void testMultipleSinks() {
        RedisSink sink1 = new RedisSink("localhost", 6379);
        RedisSink sink2 = new RedisSink("localhost", 6379);

        assertNotNull(sink1);
        assertNotNull(sink2);
        assertNotSame(sink1, sink2);
    }

    @Test
    @DisplayName("Should create sinks with different hosts")
    public void testDifferentHosts() {
        RedisSink sink1 = new RedisSink("host1", 6379);
        RedisSink sink2 = new RedisSink("host2", 6379);

        assertNotNull(sink1);
        assertNotNull(sink2);
    }

    @Test
    @DisplayName("Should create sinks with different ports")
    public void testDifferentPorts() {
        RedisSink sink1 = new RedisSink("localhost", 6379);
        RedisSink sink2 = new RedisSink("localhost", 6380);

        assertNotNull(sink1);
        assertNotNull(sink2);
    }
}
