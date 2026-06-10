package com.pipeline.functions;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Tests for {@link FeatureFunction} plumbing that does not require a running
 * Flink keyed-state context: timestamp normalisation and config parsing. The
 * indicator math itself is covered by {@link IndicatorsTest}.
 */
public class FeatureFunctionTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    // 2026-01-01T00:00:00Z
    private static final long EPOCH_2026_MS = 1767225600000L;

    private static JsonNode json(String raw) throws Exception {
        return MAPPER.readTree(raw);
    }

    @Test
    @DisplayName("FeatureFunction class exists")
    public void exists() {
        assertNotNull(FeatureFunction.class);
    }

    @Test
    @DisplayName("parses ISO-8601 Zulu timestamp")
    public void parseIsoZulu() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"2026-01-01T00:00:00Z\"")));
    }

    @Test
    @DisplayName("parses ISO-8601 with offset")
    public void parseIsoOffset() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"2026-01-01T07:00:00+07:00\"")));
    }

    @Test
    @DisplayName("parses ISO-8601 with millis")
    public void parseIsoMillis() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"2026-01-01T00:00:00.000Z\"")));
    }

    @Test
    @DisplayName("parses space-separated datetime (UTC assumed)")
    public void parseSpaceDatetime() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"2026-01-01 00:00:00.000\"")));
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"2026-01-01 00:00:00\"")));
    }

    @Test
    @DisplayName("parses epoch seconds")
    public void parseEpochSeconds() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("1767225600")));
    }

    @Test
    @DisplayName("parses epoch milliseconds")
    public void parseEpochMillis() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("1767225600000")));
    }

    @Test
    @DisplayName("parses numeric-string epoch seconds")
    public void parseNumericString() throws Exception {
        assertEquals(EPOCH_2026_MS, FeatureFunction.parseEpochMillis(json("\"1767225600\"")));
    }

    @Test
    @DisplayName("returns null for unparseable / missing / empty timestamps")
    public void parseGarbage() throws Exception {
        assertNull(FeatureFunction.parseEpochMillis(json("\"not-a-date\"")));
        assertNull(FeatureFunction.parseEpochMillis(json("\"\"")));
        assertNull(FeatureFunction.parseEpochMillis(json("null")));
        assertNull(FeatureFunction.parseEpochMillis(null));
    }

    @Test
    @DisplayName("IndicatorConfig.fromEnv yields Rust-parity defaults")
    public void configDefaults() {
        IndicatorConfig cfg = IndicatorConfig.fromEnv();
        assertEquals(14, cfg.momentumPeriod);
        assertEquals(20, cfg.deviationBandsPeriod);
        assertEquals(20, cfg.secondaryAvgPeriod);
        assertEquals(14, cfg.dispersionPeriod);
        assertEquals(200, cfg.windowSize);
        assertEquals(9, cfg.macdSignalPeriod);
        assertEquals(0, cfg.rollingMeanPeriods.length);
        assertEquals(0, cfg.expAvgPeriods.length);
    }

    @Test
    @DisplayName("IndicatorConfig.parsePeriods handles CSV and empty")
    public void parsePeriods() {
        assertArrayEquals(new int[] {7, 14}, IndicatorConfig.parsePeriods("7,14"));
        assertArrayEquals(new int[] {12, 26}, IndicatorConfig.parsePeriods(" 12 , 26 "));
        assertEquals(0, IndicatorConfig.parsePeriods("").length);
        assertEquals(0, IndicatorConfig.parsePeriods("   ").length);
    }
}
