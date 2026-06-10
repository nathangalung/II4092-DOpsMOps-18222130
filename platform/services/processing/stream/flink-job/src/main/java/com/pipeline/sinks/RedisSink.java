package com.pipeline.sinks;

import io.lettuce.core.RedisClient;
import io.lettuce.core.RedisURI;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.async.RedisAsyncCommands;
import org.apache.flink.api.connector.sink2.Sink;
import org.apache.flink.api.connector.sink2.SinkWriter;
import org.apache.flink.api.connector.sink2.WriterInitContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.IOException;
import java.io.Serializable;

/**
 * Valkey sink using Lettuce async client (Redis-RESP wire protocol).
 * Class name retains "Redis" prefix because the underlying client is the
 * Lettuce {@code io.lettuce.core.RedisClient} type — Valkey 9 is fully
 * drop-in (BSD-3-Clause vs Redis 8 AGPL).
 * Stores features keyed by symbol.
 * Updated for Flink 2.x Sink API.
 */
public class RedisSink implements Sink<String>, Serializable {
    private static final long serialVersionUID = 1L;
    private static final Logger LOG = LoggerFactory.getLogger(RedisSink.class);

    private final String host;
    private final int port;
    private final String password;
    private final String keyPrefix;

    public RedisSink(String host, int port, String password, String keyPrefix) {
        this.host = host;
        this.port = port;
        // Normalise empty string to null so RedisURI.Builder doesn't call
        // AUTH with a blank credential against a no-auth dev Valkey.
        this.password = (password == null || password.isEmpty()) ? null : password;
        // Per-stream key namespace (e.g. "features:trades:"). Supplied by
        // StreamJob from STREAM_{NAME}_KEY_PREFIX so each stream owns a
        // distinct Valkey keyspace and never clobbers another writer's
        // `features:{symbol}` (the online feature cache is owned solely by
        // the feature-engine service). Falls back to the legacy bare
        // "features:" only if a caller passes null/empty — StreamJob always
        // supplies a namespaced default.
        this.keyPrefix = (keyPrefix == null || keyPrefix.isEmpty()) ? "features:" : keyPrefix;
    }

    @Override
    public SinkWriter<String> createWriter(WriterInitContext context) throws IOException {
        return new RedisSinkWriter(host, port, password, keyPrefix);
    }

    /**
     * The actual writer implementation
     */
    private static class RedisSinkWriter implements SinkWriter<String> {
        private static final Logger LOG = LoggerFactory.getLogger(RedisSinkWriter.class);
        private static final ObjectMapper MAPPER = new ObjectMapper();
        private static final int TTL_SECONDS = 3600;

        private final RedisClient client;
        private final StatefulRedisConnection<String, String> connection;
        private final RedisAsyncCommands<String, String> commands;
        private final String keyPrefix;

        public RedisSinkWriter(String host, int port, String password, String keyPrefix) {
            this.keyPrefix = keyPrefix;
            // RedisURI.Builder lets us pass the password as a separate field,
            // avoiding hand-assembled URI strings and the escaping concerns
            // they bring. Logged URI omits the credential for safety.
            RedisURI.Builder uriBuilder = RedisURI.Builder.redis(host, port);
            if (password != null) {
                uriBuilder.withPassword(password.toCharArray());
            }
            RedisURI uri = uriBuilder.build();
            this.client = RedisClient.create(uri);
            this.connection = client.connect();
            this.commands = connection.async();
            LOG.info("Connected to Valkey (RESP): redis://{}:{} (auth={})",
                host, port, password != null);
        }

        @Override
        public void write(String value, Context context) throws IOException {
            try {
                JsonNode parsed = MAPPER.readTree(value);
                JsonNode symbolNode = parsed.get("symbol");
                if (symbolNode == null || symbolNode.isNull()) {
                    LOG.warn("Valkey sink: record missing 'symbol' — skipped");
                    return;
                }
                String symbol = symbolNode.asText();
                String key = keyPrefix + symbol;

                // The online-cache payload is the indicator map ONLY. Strip the
                // routing/scoring fields (symbol, timestamp) so the stored value
                // is a pure {feature: number} object — the exact shape the
                // feature-cache (BTreeMap<String,f64>) and gateway readers
                // expect, and byte-compatible with the historical feature-engine
                // writer (which cached the indicator map alone under the same
                // bare `features:{symbol}` key).
                ObjectNode payload = (ObjectNode) parsed;
                payload.remove("symbol");
                JsonNode tsNode = payload.remove("timestamp");
                String stored = MAPPER.writeValueAsString(payload);

                // Latest-value cache (idempotent, last-write-wins) with TTL.
                commands.setex(key, TTL_SECONDS, stored);

                // Optional per-symbol history (sorted set scored by event time).
                // Only when the record carried a numeric timestamp; the cached
                // payload itself never includes it.
                if (tsNode != null && tsNode.canConvertToLong()) {
                    String historyKey = keyPrefix + "history:" + symbol;
                    commands.zadd(historyKey, tsNode.asLong(), stored);
                    commands.zremrangebyrank(historyKey, 0, -1000);
                }
            } catch (Exception e) {
                LOG.error("Valkey sink error", e);
                throw new IOException("Failed to write to Valkey", e);
            }
        }

        @Override
        public void flush(boolean endOfInput) throws IOException {
            // Async commands auto-flush, but we can sync here if needed
            try {
                commands.ping().get();
            } catch (Exception e) {
                LOG.warn("Flush ping failed", e);
            }
        }

        @Override
        public void close() throws Exception {
            if (connection != null) connection.close();
            if (client != null) client.shutdown();
            LOG.info("Valkey connection closed");
        }
    }
}
