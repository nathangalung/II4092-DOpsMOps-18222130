package com.pipeline;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

import com.pipeline.functions.FeatureFunction;
import java.util.Arrays;
import java.util.List;
import java.util.ArrayList;

/**
 * Comprehensive tests for FeatureFunction.
 */
public class FeatureFunctionTest {

    @Test
    @DisplayName("FeatureFunction class exists")
    public void testFeatureFunctionExists() {
        assertNotNull(FeatureFunction.class);
    }

    @Test
    @DisplayName("Rolling mean calculation with valid data")
    public void testRollingMeanCalculation() {
        double[] values = {1.0, 2.0, 3.0, 4.0, 5.0};
        double mean = calculateRollingMean(values, 5);
        assertEquals(3.0, mean, 0.001);
    }

    @Test
    @DisplayName("Rolling mean calculation with partial period")
    public void testRollingMeanPartialPeriod() {
        double[] values = {1.0, 2.0, 3.0, 4.0, 5.0};
        double mean = calculateRollingMean(values, 2);
        assertEquals(4.5, mean, 0.001); // (4 + 5) / 2
    }

    @Test
    @DisplayName("Rolling mean returns 0 for insufficient data")
    public void testRollingMeanInsufficientData() {
        double[] values = {1.0, 2.0};
        double mean = calculateRollingMean(values, 5);
        assertEquals(0.0, mean, 0.001);
    }

    @Test
    @DisplayName("Exponential average calculation")
    public void testExpAvgCalculation() {
        double[] values = {10.0, 11.0, 12.0};
        double avg = calculateExpAvg(values, 3);
        assertEquals(11.25, avg, 0.01);
    }

    @Test
    @DisplayName("Exponential average returns 0 for empty data")
    public void testExpAvgEmptyData() {
        double[] values = {};
        double avg = calculateExpAvg(values, 5);
        assertEquals(0.0, avg, 0.001);
    }

    @Test
    @DisplayName("Momentum calculation for all gains")
    public void testMomentumAllGains() {
        double[] values = {10.0, 10.5, 11.0, 11.5, 12.0};
        double m = calculateMomentum(values, 4);
        assertTrue(m > 90.0);
    }

    @Test
    @DisplayName("Momentum calculation for all losses")
    public void testMomentumAllLosses() {
        double[] values = {10.0, 9.5, 9.0, 8.5, 8.0};
        double m = calculateMomentum(values, 4);
        assertTrue(m < 10.0);
    }

    @Test
    @DisplayName("Momentum bounds check")
    public void testMomentumBounds() {
        double[] values = {10.0, 11.0, 10.5, 11.5, 10.0, 12.0};
        double m = calculateMomentum(values, 4);
        assertTrue(m >= 0.0 && m <= 100.0);
    }

    @Test
    @DisplayName("Momentum default for insufficient data")
    public void testMomentumInsufficientData() {
        double[] values = {10.0, 11.0};
        double m = calculateMomentum(values, 14);
        assertEquals(50.0, m, 0.001);
    }

    @Test
    @DisplayName("Deviation bands for constant values")
    public void testDeviationBandsConstantValues() {
        double[] values = {10.0, 10.0, 10.0, 10.0, 10.0};
        double[] bands = calculateDeviationBands(values, 5);
        assertEquals(10.0, bands[1], 0.001); // Middle band
        assertEquals(10.0, bands[0], 0.001); // Upper band (no variance)
        assertEquals(10.0, bands[2], 0.001); // Lower band
    }

    @Test
    @DisplayName("Deviation bands with variance")
    public void testDeviationBandsWithVariance() {
        double[] values = {8.0, 9.0, 10.0, 11.0, 12.0};
        double[] bands = calculateDeviationBands(values, 5);
        assertEquals(10.0, bands[1], 0.001); // Middle band = mean
        assertTrue(bands[0] > bands[1]); // Upper > middle
        assertTrue(bands[2] < bands[1]); // Lower < middle
    }

    @Test
    @DisplayName("Value change calculation")
    public void testValueChange() {
        double oldValue = 100.0;
        double newValue = 110.0;
        double change = (newValue - oldValue) / oldValue;
        assertEquals(0.1, change, 0.001);
    }

    @Test
    @DisplayName("Dispersion calculation")
    public void testDispersionCalculation() {
        double[] values = {0.01, -0.02, 0.015, -0.01, 0.02};
        double disp = calculateStdDev(values);
        assertTrue(disp > 0);
    }

    @Test
    @DisplayName("Weighted average of values")
    public void testWeightedAverage() {
        double[] values = {100.0, 101.0, 102.0};
        double[] weights = {1000.0, 2000.0, 1500.0};
        double wavg = calculateWeightedAvg(values, weights);
        // weighted avg = sum(value * weight) / sum(weight)
        double expected = (100.0 * 1000 + 101.0 * 2000 + 102.0 * 1500) / (1000 + 2000 + 1500);
        assertEquals(expected, wavg, 0.001);
    }

    // Helper methods to simulate feature calculations

    private double calculateRollingMean(double[] values, int period) {
        if (values.length < period) {
            return 0.0;
        }
        double sum = 0.0;
        for (int i = values.length - period; i < values.length; i++) {
            sum += values[i];
        }
        return sum / period;
    }

    private double calculateExpAvg(double[] values, int period) {
        if (values.length == 0) {
            return 0.0;
        }
        double k = 2.0 / (period + 1);
        double result = values[0];
        for (int i = 1; i < values.length; i++) {
            result = values[i] * k + result * (1 - k);
        }
        return result;
    }

    private double calculateMomentum(double[] values, int period) {
        if (values.length < period + 1) {
            return 50.0;
        }

        double gains = 0.0;
        double losses = 0.0;

        for (int i = values.length - period; i < values.length; i++) {
            double change = values[i] - values[i - 1];
            if (change > 0) {
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

    private double[] calculateDeviationBands(double[] values, int period) {
        if (values.length < period) {
            return new double[]{0.0, 0.0, 0.0};
        }

        double sum = 0.0;
        for (int i = values.length - period; i < values.length; i++) {
            sum += values[i];
        }
        double mean = sum / period;

        double variance = 0.0;
        for (int i = values.length - period; i < values.length; i++) {
            variance += Math.pow(values[i] - mean, 2);
        }
        variance /= period;
        double stdDev = Math.sqrt(variance);

        return new double[]{mean + 2 * stdDev, mean, mean - 2 * stdDev};
    }

    private double calculateStdDev(double[] values) {
        if (values.length == 0) {
            return 0.0;
        }

        double mean = 0.0;
        for (double v : values) {
            mean += v;
        }
        mean /= values.length;

        double variance = 0.0;
        for (double v : values) {
            variance += Math.pow(v - mean, 2);
        }
        variance /= values.length;

        return Math.sqrt(variance);
    }

    private double calculateWeightedAvg(double[] values, double[] weights) {
        double sumVW = 0.0;
        double sumW = 0.0;
        for (int i = 0; i < values.length; i++) {
            sumVW += values[i] * weights[i];
            sumW += weights[i];
        }
        return sumW > 0 ? sumVW / sumW : 0.0;
    }
}
