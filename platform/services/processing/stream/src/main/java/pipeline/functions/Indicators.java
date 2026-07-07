package pipeline.functions;

import java.util.List;
import java.util.Map;
import java.util.TreeMap;

/**
 * Pure, stateless time-series indicator math - the Java counterpart of the Rust
 * feature-engine {@code indicators.rs}. Every formula here is a faithful port of
 * its Rust sibling so the Flink stream processor and the (retired) Rust engine
 * are byte-for-byte interchangeable on the same input window. Kept free of any
 * Flink / Jackson types so it is unit-testable in isolation (see IndicatorsTest)
 * - those tests ARE the no-lost-service proof for the feature-engine to Flink
 * cutover.
 *
 * <p>All operations are generic windowed statistics (means, EMA, momentum,
 * dispersion) applicable to any numeric series - no domain logic. The MACD-style
 * <em>signal line</em> is intentionally NOT here: it requires per-key state
 * (an EMA over the convergence series itself) and therefore lives in
 * {@link FeatureFunction}.
 */
public final class Indicators {
    private Indicators() {}

    /** Simple moving average of the last {@code period} values; 0 if too short. */
    public static double rollingMean(List<Double> values, int period) {
        if (period <= 0 || values.size() < period) {
            return 0.0;
        }
        double sum = 0.0;
        for (int i = values.size() - period; i < values.size(); i++) {
            sum += values.get(i);
        }
        return sum / period;
    }

    /**
     * Exponential moving average over the full series, seeded at the first
     * element. Mirrors Rust {@code compute_exp_avg}: returns 0 only when EMPTY
     * (NOT when shorter than {@code period}); otherwise smooths from values[0].
     */
    public static double expAvg(List<Double> values, int period) {
        if (values.isEmpty()) {
            return 0.0;
        }
        double k = 2.0 / (period + 1.0);
        double result = values.get(0);
        for (int i = 1; i < values.size(); i++) {
            result = values.get(i) * k + result * (1.0 - k);
        }
        return result;
    }

    /**
     * RSI-style momentum oscillator over the last {@code period} deltas.
     * Mirrors Rust {@code compute_momentum}: 50 when fewer than period+1
     * points, 100 when there are no losses.
     */
    public static double momentum(List<Double> values, int period) {
        if (values.size() < period + 1) {
            return 50.0;
        }
        double gains = 0.0;
        double losses = 0.0;
        for (int i = values.size() - period; i < values.size(); i++) {
            double change = values.get(i) - values.get(i - 1);
            if (change > 0.0) {
                gains += change;
            } else {
                losses -= change;
            }
        }
        double avgGain = gains / period;
        double avgLoss = losses / period;
        if (avgLoss == 0.0) {
            return 100.0;
        }
        double rs = avgGain / avgLoss;
        return 100.0 - (100.0 / (1.0 + rs));
    }

    /**
     * Deviation bands (mean ± 2·σ) over the last {@code period} values, where σ
     * is the POPULATION standard deviation. Mirrors Rust
     * {@code compute_deviation_bands}. Returns {@code [upper, middle, lower]};
     * all zero when fewer than {@code period} points.
     */
    public static double[] deviationBands(List<Double> values, int period) {
        if (period <= 0 || values.size() < period) {
            return new double[] {0.0, 0.0, 0.0};
        }
        double mean = rollingMean(values, period);
        double variance = 0.0;
        for (int i = values.size() - period; i < values.size(); i++) {
            double d = values.get(i) - mean;
            variance += d * d;
        }
        variance /= period;
        double std = Math.sqrt(variance);
        return new double[] {mean + 2.0 * std, mean, mean - 2.0 * std};
    }

    /**
     * POPULATION standard deviation over the last {@code period} values.
     * Mirrors Rust {@code compute_dispersion} (NOT a sample/whole-window std);
     * 0 when fewer than {@code period} points.
     */
    public static double dispersion(List<Double> values, int period) {
        if (period <= 0 || values.size() < period) {
            return 0.0;
        }
        double mean = rollingMean(values, period);
        double variance = 0.0;
        for (int i = values.size() - period; i < values.size(); i++) {
            double d = values.get(i) - mean;
            variance += d * d;
        }
        variance /= period;
        return Math.sqrt(variance);
    }

    /**
     * Percent change between the last two values. Mirrors Rust
     * {@code compute_value_change}: ×100 (percent), 0 when fewer than two
     * points or the previous value is zero.
     */
    public static double valueChange(List<Double> values) {
        if (values.size() < 2) {
            return 0.0;
        }
        double current = values.get(values.size() - 1);
        double previous = values.get(values.size() - 2);
        if (previous == 0.0) {
            return 0.0;
        }
        return (current - previous) / previous * 100.0;
    }

    /**
     * Compute every configured STATELESS indicator from the primary/secondary
     * series, mirroring Rust {@code compute_all}. Returns a sorted map (matches
     * the serde {@code BTreeMap} key ordering of the feature-engine cache).
     *
     * <p>The trend (MACD) triple is added by {@link FeatureFunction} because its
     * signal line is stateful; everything else is self-contained here.
     */
    public static Map<String, Double> computeAll(
            List<Double> primaryValues, List<Double> secondaryValues, IndicatorConfig config) {
        Map<String, Double> features = new TreeMap<>();
        if (primaryValues.isEmpty()) {
            return features;
        }

        features.put("value", primaryValues.get(primaryValues.size() - 1));

        for (int period : config.rollingMeanPeriods) {
            features.put("rolling_mean_" + period, rollingMean(primaryValues, period));
        }
        for (int period : config.expAvgPeriods) {
            features.put("rolling_ema_" + period, expAvg(primaryValues, period));
        }

        features.put("momentum_" + config.momentumPeriod, momentum(primaryValues, config.momentumPeriod));

        if (config.deviationBandsEnabled) {
            double[] bands = deviationBands(primaryValues, config.deviationBandsPeriod);
            features.put("band_upper", bands[0]);
            features.put("band_middle", bands[1]);
            features.put("band_lower", bands[2]);
        }

        if (!secondaryValues.isEmpty()) {
            features.put("secondary_avg", rollingMean(secondaryValues, config.secondaryAvgPeriod));
        }

        features.put("value_change", valueChange(primaryValues));
        features.put("dispersion", dispersion(primaryValues, config.dispersionPeriod));

        return features;
    }
}
