package com.pipeline.functions;

/**
 * Configurable indicator computation parameters.
 *
 * <p>Direct Java counterpart of the Rust feature-engine {@code IndicatorConfig}
 * (config.rs). Every period and flag is supplied by the use-case at deploy time
 * via {@code FLINK_*} environment variables — no domain logic is hardcoded.
 * Defaults mirror the Rust {@code IndicatorConfig::default()} so the two stream
 * processors are behaviourally interchangeable.
 */
public final class IndicatorConfig {
    public final int[] rollingMeanPeriods;
    public final int[] expAvgPeriods;
    public final int momentumPeriod;
    public final boolean trendConvergenceEnabled;
    public final int deviationBandsPeriod;
    public final boolean deviationBandsEnabled;
    public final int secondaryAvgPeriod;
    public final int dispersionPeriod;
    public final int windowSize;
    /** Signal-line period for the MACD-style trend signal (standard MACD = 9). */
    public final int macdSignalPeriod;

    public IndicatorConfig(
            int[] rollingMeanPeriods,
            int[] expAvgPeriods,
            int momentumPeriod,
            boolean trendConvergenceEnabled,
            int deviationBandsPeriod,
            boolean deviationBandsEnabled,
            int secondaryAvgPeriod,
            int dispersionPeriod,
            int windowSize,
            int macdSignalPeriod) {
        this.rollingMeanPeriods = rollingMeanPeriods;
        this.expAvgPeriods = expAvgPeriods;
        this.momentumPeriod = momentumPeriod;
        this.trendConvergenceEnabled = trendConvergenceEnabled;
        this.deviationBandsPeriod = deviationBandsPeriod;
        this.deviationBandsEnabled = deviationBandsEnabled;
        this.secondaryAvgPeriod = secondaryAvgPeriod;
        this.dispersionPeriod = dispersionPeriod;
        this.windowSize = windowSize;
        this.macdSignalPeriod = macdSignalPeriod;
    }

    /**
     * Build from environment variables. Mirrors config.rs defaults so an unset
     * environment yields the same indicator set as the Rust engine's defaults.
     */
    public static IndicatorConfig fromEnv() {
        return new IndicatorConfig(
            parsePeriods(env("FLINK_ROLLING_MEAN_PERIODS", "")),
            parsePeriods(env("FLINK_EXP_AVG_PERIODS", "")),
            parseInt(env("FLINK_MOMENTUM_PERIOD", "14")),
            parseBool(env("FLINK_TREND_CONVERGENCE_ENABLED", "false")),
            parseInt(env("FLINK_DEVIATION_BANDS_PERIOD", "20")),
            parseBool(env("FLINK_DEVIATION_BANDS_ENABLED", "false")),
            parseInt(env("FLINK_SECONDARY_AVG_PERIOD", "20")),
            parseInt(env("FLINK_DISPERSION_PERIOD", "14")),
            parseInt(env("FLINK_WINDOW_SIZE", "200")),
            parseInt(env("FLINK_MACD_SIGNAL_PERIOD", "9")));
    }

    private static String env(String key, String def) {
        String v = System.getenv(key);
        return (v == null || v.isEmpty()) ? def : v;
    }

    /** Parse a comma-separated period list; empty string yields an empty array. */
    static int[] parsePeriods(String csv) {
        if (csv == null || csv.trim().isEmpty()) {
            return new int[0];
        }
        String[] parts = csv.split(",");
        int[] periods = new int[parts.length];
        for (int i = 0; i < parts.length; i++) {
            periods[i] = Integer.parseInt(parts[i].trim());
        }
        return periods;
    }

    private static int parseInt(String s) {
        return Integer.parseInt(s.trim());
    }

    private static boolean parseBool(String s) {
        return Boolean.parseBoolean(s.trim());
    }
}
