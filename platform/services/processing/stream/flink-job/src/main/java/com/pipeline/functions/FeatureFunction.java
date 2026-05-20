package com.pipeline.functions;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.apache.commons.math3.stat.descriptive.DescriptiveStatistics;
import org.apache.flink.api.common.functions.OpenContext;
import org.apache.flink.api.common.state.ListState;
import org.apache.flink.api.common.state.ListStateDescriptor;
import org.apache.flink.api.common.typeinfo.Types;
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;

/**
 * Keyed process function for feature computation.
 * Maintains state per symbol for time-series indicators.
 * All indicator types and periods are configurable via environment variables.
 * Updated for Flink 2.x API.
 */
public class FeatureFunction extends KeyedProcessFunction<String, String, String> {
    private static final Logger LOG = LoggerFactory.getLogger(FeatureFunction.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();
    // Configurable fields — read from env vars, set via use-case ConfigMap
    private final String primaryValueField;
    private final String secondaryValueField;
    private final int[] rollingMeanPeriods;
    private final int[] expAvgPeriods;
    private final int momentumPeriod;
    private final int windowSize;
    private final int minDataPoints;

    private transient ListState<Double> primaryValueHistory;
    private transient ListState<Double> secondaryValueHistory;

    public FeatureFunction() {
        // Read configuration from environment variables (set via ConfigMap)
        this.primaryValueField = System.getenv().getOrDefault("PRIMARY_VALUE_FIELD", "value");
        this.secondaryValueField = System.getenv().getOrDefault("SECONDARY_VALUE_FIELD", "value_2");
        this.rollingMeanPeriods = parsePeriods(System.getenv().getOrDefault("FLINK_ROLLING_MEAN_PERIODS", "7,14"));
        this.expAvgPeriods = parsePeriods(System.getenv().getOrDefault("FLINK_EXP_AVG_PERIODS", "12,26"));
        this.momentumPeriod = Integer.parseInt(System.getenv().getOrDefault("FLINK_MOMENTUM_PERIOD", "14"));
        this.windowSize = Integer.parseInt(System.getenv().getOrDefault("FLINK_WINDOW_SIZE", "30"));
        this.minDataPoints = Math.max(momentumPeriod, maxPeriod(rollingMeanPeriods, expAvgPeriods));
    }

    private static int[] parsePeriods(String csv) {
        String[] parts = csv.split(",");
        int[] periods = new int[parts.length];
        for (int i = 0; i < parts.length; i++) {
            periods[i] = Integer.parseInt(parts[i].trim());
        }
        return periods;
    }

    private static int maxPeriod(int[]... arrays) {
        int max = 0;
        for (int[] arr : arrays) {
            for (int v : arr) {
                if (v > max) max = v;
            }
        }
        return max;
    }

    @Override
    public void open(OpenContext openContext) throws Exception {
        primaryValueHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("primary_values", Types.DOUBLE));
        secondaryValueHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("secondary_values", Types.DOUBLE));
    }

    @Override
    public void processElement(String value, Context ctx, Collector<String> out) throws Exception {
        JsonNode input = MAPPER.readTree(value);

        // Skip records that don't have the expected primary value field (e.g., ticker data)
        if (!input.has(primaryValueField) || input.get(primaryValueField).isNull()) {
            return;
        }

        double primaryValue = input.get(primaryValueField).asDouble();
        double secondaryValue = input.has(secondaryValueField) ? input.get(secondaryValueField).asDouble() : 0.0;
        String symbol = input.get("symbol").asText();
        long timestamp = input.get("timestamp").asLong();

        // Update state
        List<Double> primaryValues = toList(primaryValueHistory.get());
        List<Double> secondaryValues = toList(secondaryValueHistory.get());

        primaryValues.add(primaryValue);
        secondaryValues.add(secondaryValue);

        // Keep window size
        if (primaryValues.size() > windowSize) {
            primaryValues = primaryValues.subList(primaryValues.size() - windowSize, primaryValues.size());
            secondaryValues = secondaryValues.subList(secondaryValues.size() - windowSize, secondaryValues.size());
        }

        primaryValueHistory.update(primaryValues);
        secondaryValueHistory.update(secondaryValues);

        // Compute features if enough data
        if (primaryValues.size() >= minDataPoints) {
            ObjectNode features = MAPPER.createObjectNode();
            features.put("symbol", symbol);
            features.put("timestamp", timestamp);
            features.put(primaryValueField, primaryValue);
            features.put(secondaryValueField, secondaryValue);

            // Rolling mean — configurable periods
            for (int period : rollingMeanPeriods) {
                features.put("rolling_mean_" + period, rollingMean(primaryValues, period));
            }

            // Exponential average — configurable periods
            for (int period : expAvgPeriods) {
                features.put("rolling_ema_" + period, expAvg(primaryValues, period));
            }

            // Momentum — configurable period
            features.put("momentum_" + momentumPeriod, momentum(primaryValues, momentumPeriod));

            // Dispersion
            features.put("dispersion", dispersion(primaryValues));

            // Value change
            if (primaryValues.size() >= 2) {
                double prevValue = primaryValues.get(primaryValues.size() - 2);
                features.put("value_change", (primaryValue - prevValue) / prevValue);
            }

            out.collect(MAPPER.writeValueAsString(features));
        }
    }

    private List<Double> toList(Iterable<Double> iter) {
        List<Double> list = new ArrayList<>();
        iter.forEach(list::add);
        return list;
    }

    /** Rolling mean over a window period */
    private double rollingMean(List<Double> values, int period) {
        if (values.size() < period) return 0;
        return values.subList(values.size() - period, values.size())
            .stream().mapToDouble(d -> d).average().orElse(0);
    }

    /** Exponential weighted average */
    private double expAvg(List<Double> values, int period) {
        if (values.size() < period) return 0;
        double multiplier = 2.0 / (period + 1);
        double result = values.get(0);
        for (int i = 1; i < values.size(); i++) {
            result = (values.get(i) - result) * multiplier + result;
        }
        return result;
    }

    /** Momentum oscillator */
    private double momentum(List<Double> values, int period) {
        if (values.size() < period + 1) return 50;

        double gains = 0, losses = 0;
        for (int i = values.size() - period; i < values.size(); i++) {
            double change = values.get(i) - values.get(i - 1);
            if (change > 0) gains += change;
            else losses -= change;
        }

        if (losses == 0) return 100;
        double rs = gains / losses;
        return 100 - (100 / (1 + rs));
    }

    /** Standard deviation dispersion */
    private double dispersion(List<Double> values) {
        DescriptiveStatistics stats = new DescriptiveStatistics();
        values.forEach(stats::addValue);
        return stats.getStandardDeviation();
    }
}
