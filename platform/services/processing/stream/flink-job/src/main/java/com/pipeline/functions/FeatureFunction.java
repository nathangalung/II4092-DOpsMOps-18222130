package com.pipeline.functions;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.pipeline.Tags;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.state.ListState;
import org.apache.flink.api.common.state.ListStateDescriptor;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * Keyed feature-computation function — the Flink stream processor that owns the
 * crypto speed layer (replaces the retired Rust feature-engine).
 *
 * <p>State per symbol: the primary value window (e.g. close), the secondary
 * value window (e.g. volume), and — when trend convergence is enabled — the
 * MACD-line window used to derive a real stateful signal line.
 *
 * <p>Two outputs per tick (emitted EVERY tick, like the feature-engine; the
 * indicators self-gate to warm-up defaults rather than the operator gating
 * emission):
 * <ul>
 *   <li><b>main</b> → the full feature record (input passthrough + indicators)
 *       with an ISO-normalised string {@code timestamp}, destined for the Kafka
 *       → ClickHouse bronze contract.</li>
 *   <li><b>{@link Tags#CACHE_TAG}</b> → the indicator-only projection (plus
 *       {@code symbol} + numeric {@code timestamp} for sink routing/scoring),
 *       destined for the Valkey online cache under {@code features:{symbol}}.</li>
 * </ul>
 *
 * <p>All indicator math is the faithful Rust-parity port in {@link Indicators};
 * the only deliberate divergence is the trend signal line — see
 * {@link #computeTrend} — which is a correct stateful MACD EMA rather than the
 * feature-engine's {@code convergence*0.2} approximation.
 */
public class FeatureFunction extends KeyedProcessFunction<String, String, String> {
    private static final Logger LOG = LoggerFactory.getLogger(FeatureFunction.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Bronze timestamp format — matches the feature-engine's "%Y-%m-%d %H:%M:%S%.3f". */
    private static final DateTimeFormatter BRONZE_TS =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS");
    /** Tolerated input string timestamp with a space separator (UTC assumed). */
    private static final DateTimeFormatter SPACE_TS =
        DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss[.SSS]");
    /** Below this magnitude a numeric timestamp is seconds, not milliseconds. */
    private static final long EPOCH_MILLIS_THRESHOLD = 100_000_000_000L;

    private final String primaryValueField;
    private final String secondaryValueField;
    private final IndicatorConfig config;

    private transient ListState<Double> primaryValueHistory;
    private transient ListState<Double> secondaryValueHistory;
    private transient ListState<Double> macdHistory;

    public FeatureFunction() {
        this.primaryValueField = envOrDefault("PRIMARY_VALUE_FIELD", "value");
        this.secondaryValueField = envOrDefault("SECONDARY_VALUE_FIELD", "value_2");
        this.config = IndicatorConfig.fromEnv();
    }

    private static String envOrDefault(String key, String def) {
        String v = System.getenv(key);
        return (v == null || v.isEmpty()) ? def : v;
    }

    @Override
    public void open(OpenContext openContext) throws Exception {
        primaryValueHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("primary_values", Types.DOUBLE));
        secondaryValueHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("secondary_values", Types.DOUBLE));
        macdHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("macd_line", Types.DOUBLE));
    }

    @Override
    public void processElement(String value, Context ctx, Collector<String> out) throws Exception {
        JsonNode input = MAPPER.readTree(value);

        // Skip records lacking the primary value field (e.g. ticker-only data).
        if (!input.has(primaryValueField) || input.get(primaryValueField).isNull()) {
            return;
        }
        JsonNode symbolNode = input.get("symbol");
        if (symbolNode == null || symbolNode.isNull()) {
            return;
        }
        String symbol = symbolNode.asText();

        // Robustly resolve the event time (ISO-8601 string, space-separated
        // datetime, or epoch s/ms). Drop the record if unparseable rather than
        // emit a corrupt 1970 timestamp into the bronze table.
        Long epochMillis = parseEpochMillis(input.get("timestamp"));
        if (epochMillis == null) {
            LOG.warn("Unparseable timestamp for symbol={} — record skipped", symbol);
            return;
        }

        double primaryValue = input.get(primaryValueField).asDouble();
        boolean hasSecondary = input.has(secondaryValueField) && !input.get(secondaryValueField).isNull();

        // --- Update windowed state ---
        List<Double> primaryValues = toList(primaryValueHistory.get());
        primaryValues.add(primaryValue);
        trim(primaryValues, config.windowSize);
        primaryValueHistory.update(primaryValues);

        List<Double> secondaryValues = toList(secondaryValueHistory.get());
        if (hasSecondary) {
            secondaryValues.add(input.get(secondaryValueField).asDouble());
            trim(secondaryValues, config.windowSize);
            secondaryValueHistory.update(secondaryValues);
        }

        // --- Stateless indicators (faithful feature-engine parity) ---
        Map<String, Double> features = Indicators.computeAll(primaryValues, secondaryValues, config);

        // --- Stateful trend (MACD) triple ---
        if (config.trendConvergenceEnabled) {
            computeTrend(primaryValues, features);
        }

        // --- Main output: full bronze record (passthrough + indicators) ---
        ObjectNode bronze = MAPPER.createObjectNode();
        bronze.put("symbol", symbol);
        bronze.put("timestamp", formatBronzeTs(epochMillis));
        // Passthrough every original field except the ones we set explicitly,
        // mirroring the feature-engine's flattened original_values (OHLCV + source).
        Iterator<Map.Entry<String, JsonNode>> fields = input.fields();
        while (fields.hasNext()) {
            Map.Entry<String, JsonNode> e = fields.next();
            String name = e.getKey();
            if (!name.equals("symbol") && !name.equals("timestamp")) {
                bronze.set(name, e.getValue());
            }
        }
        putFeatures(bronze, features);
        out.collect(MAPPER.writeValueAsString(bronze));

        // --- Side output: indicator-only online-cache projection ---
        ObjectNode cache = MAPPER.createObjectNode();
        cache.put("symbol", symbol);
        cache.put("timestamp", epochMillis);
        putFeatures(cache, features);
        ctx.output(Tags.CACHE_TAG, MAPPER.writeValueAsString(cache));
    }

    /**
     * Append the convergence (MACD line) to per-key state and derive a real
     * EMA signal line + histogram. DELIBERATE divergence from the feature-engine
     * (which used {@code signal = convergence*0.2}): a proper stateful EMA over
     * the MACD line is the correct, standard MACD signal. See the speed-layer
     * ADR — the bronze stream features are not on the offline-training path, so
     * this strictly improves correctness without affecting batch↔stream parity
     * (which is asserted on volume SMA, not the trend triple).
     */
    private void computeTrend(List<Double> primaryValues, Map<String, Double> features) throws Exception {
        if (config.expAvgPeriods.length < 2) {
            return; // need a fast + slow period to form a convergence line
        }
        int fast = config.expAvgPeriods[0];
        int slow = config.expAvgPeriods[1];
        double convergence = (primaryValues.size() < slow)
            ? 0.0
            : Indicators.expAvg(primaryValues, fast) - Indicators.expAvg(primaryValues, slow);

        List<Double> macdLine = toList(macdHistory.get());
        macdLine.add(convergence);
        trim(macdLine, config.windowSize);
        macdHistory.update(macdLine);

        double signal = Indicators.expAvg(macdLine, config.macdSignalPeriod);
        double hist = convergence - signal;

        features.put("trend_convergence", convergence);
        features.put("trend_signal", signal);
        features.put("trend_hist", hist);
    }

    private static void putFeatures(ObjectNode node, Map<String, Double> features) {
        for (Map.Entry<String, Double> e : features.entrySet()) {
            node.put(e.getKey(), e.getValue());
        }
    }

    private static List<Double> toList(Iterable<Double> iter) {
        List<Double> list = new ArrayList<>();
        if (iter != null) {
            iter.forEach(list::add);
        }
        return list;
    }

    /** Keep at most {@code maxSize} trailing elements in place. */
    private static void trim(List<Double> values, int maxSize) {
        int excess = values.size() - maxSize;
        for (int i = 0; i < excess; i++) {
            values.remove(0);
        }
    }

    private static String formatBronzeTs(long epochMillis) {
        return Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC).format(BRONZE_TS);
    }

    /**
     * Parse an event timestamp into epoch milliseconds. Accepts:
     * RFC3339 / ISO-8601 (with offset or {@code Z}), a space-separated
     * {@code yyyy-MM-dd HH:mm:ss[.SSS]} datetime (UTC assumed), or a numeric
     * epoch (seconds or milliseconds). Returns {@code null} when unparseable.
     */
    static Long parseEpochMillis(JsonNode tsNode) {
        if (tsNode == null || tsNode.isNull()) {
            return null;
        }
        if (tsNode.isNumber()) {
            return normaliseEpoch(tsNode.asLong());
        }
        String s = tsNode.asText().trim();
        if (s.isEmpty()) {
            return null;
        }
        try {
            return Instant.parse(s).toEpochMilli();
        } catch (Exception ignored) {
            // not a Z/offset instant — fall through
        }
        try {
            return OffsetDateTime.parse(s).toInstant().toEpochMilli();
        } catch (Exception ignored) {
            // not an offset datetime — fall through
        }
        try {
            String normalised = s.contains("T") ? s.replace('T', ' ') : s;
            LocalDateTime ldt = LocalDateTime.parse(normalised, SPACE_TS);
            return ldt.toInstant(ZoneOffset.UTC).toEpochMilli();
        } catch (Exception ignored) {
            // not a space/T datetime — fall through
        }
        try {
            return normaliseEpoch(Long.parseLong(s));
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private static long normaliseEpoch(long v) {
        return Math.abs(v) < EPOCH_MILLIS_THRESHOLD ? v * 1000L : v;
    }
}
