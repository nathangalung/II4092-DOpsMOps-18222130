package com.pipeline.sinks;

import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for KafkaSinkFactory.
 */
public class KafkaSinkFactoryTest {

    @Test
    @DisplayName("Should create sink with valid parameters")
    public void testCreateSink() {
        KafkaSinkFactory factory = new KafkaSinkFactory("localhost:9092", "test-topic");
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle null bootstrap servers")
    public void testNullBootstrapServers() {
        assertThrows(NullPointerException.class, () -> {
            KafkaSinkFactory factory = new KafkaSinkFactory(null, "test-topic");
        });
    }

    @Test
    @DisplayName("Should handle null topic")
    public void testNullTopic() {
        assertThrows(NullPointerException.class, () -> {
            KafkaSinkFactory factory = new KafkaSinkFactory("localhost:9092", null);
        });
    }

    @Test
    @DisplayName("Should handle empty bootstrap servers")
    public void testEmptyBootstrapServers() {
        KafkaSinkFactory factory = new KafkaSinkFactory("", "test-topic");
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should handle empty topic")
    public void testEmptyTopic() {
        KafkaSinkFactory factory = new KafkaSinkFactory("localhost:9092", "");
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create sink with multiple brokers")
    public void testMultipleBrokers() {
        KafkaSinkFactory factory = new KafkaSinkFactory(
            "broker1:9092,broker2:9092,broker3:9092",
            "test-topic"
        );
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create multiple sinks with same factory")
    public void testCreateMultipleSinks() {
        KafkaSinkFactory factory = new KafkaSinkFactory("localhost:9092", "test-topic");

        KafkaSink<String> sink1 = factory.createSink();
        KafkaSink<String> sink2 = factory.createSink();

        assertNotNull(sink1);
        assertNotNull(sink2);
        assertNotSame(sink1, sink2);
    }

    @Test
    @DisplayName("Should create factory with special characters in topic")
    public void testSpecialCharactersInTopic() {
        KafkaSinkFactory factory = new KafkaSinkFactory(
            "localhost:9092",
            "test-topic_with-special.chars123"
        );
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create factory with IP address broker")
    public void testIpAddressBroker() {
        KafkaSinkFactory factory = new KafkaSinkFactory("192.168.1.100:9092", "test-topic");
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }

    @Test
    @DisplayName("Should create factory with custom port")
    public void testCustomPort() {
        KafkaSinkFactory factory = new KafkaSinkFactory("localhost:19092", "test-topic");
        KafkaSink<String> sink = factory.createSink();

        assertNotNull(sink);
    }
}
