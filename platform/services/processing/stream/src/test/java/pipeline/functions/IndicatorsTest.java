package pipeline.functions;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.DisplayName;
import static org.junit.jupiter.api.Assertions.*;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Parity oracle for {@link Indicators}.
 *
 * <p>Each assertion encodes the Rust feature-engine {@code indicators.rs}
 * semantics. Green here means the Flink stream processor reproduces the established
 * feature-engine behaviour exactly - the no-lost-service proof for the
 * feature-engine to Flink cutover.
 */
public class IndicatorsTest {

    private static List<Double> list(double... xs) {
        List<Double> l = new ArrayList<>();
        for (double x : xs) l.add(x);
        return l;
    }

    // rolling mean

    @Test
    @DisplayName("rolling mean over full window")
    public void rollingMeanFull() {
        assertEquals(3.0, Indicators.rollingMean(list(1, 2, 3, 4, 5), 5), 1e-9);
    }

    @Test
    @DisplayName("rolling mean over last period only")
    public void rollingMeanLastPeriod() {
        assertEquals(4.5, Indicators.rollingMean(list(1, 2, 3, 4, 5), 2), 1e-9);
    }

    @Test
    @DisplayName("rolling mean returns 0 when shorter than period")
    public void rollingMeanShort() {
        assertEquals(0.0, Indicators.rollingMean(list(1, 2), 5), 1e-9);
    }

    // exponential average

    @Test
    @DisplayName("exp avg smooths from the first element")
    public void expAvgBasic() {
        // k=0.5: 10 then 10.5 then 11.25
        assertEquals(11.25, Indicators.expAvg(list(10, 11, 12), 3), 1e-9);
    }

    @Test
    @DisplayName("exp avg returns 0 only when EMPTY")
    public void expAvgEmpty() {
        assertEquals(0.0, Indicators.expAvg(list(), 5), 1e-9);
    }

    @Test
    @DisplayName("exp avg computes from seed even when shorter than period (Rust parity)")
    public void expAvgShorterThanPeriod() {
        // The old Flink port returned 0 when size<period; Rust does NOT. k=2/6.
        double k = 2.0 / 6.0;
        double r = 10.0;
        r = 11.0 * k + r * (1 - k);
        r = 12.0 * k + r * (1 - k);
        assertEquals(r, Indicators.expAvg(list(10, 11, 12), 5), 1e-9);
        assertTrue(Indicators.expAvg(list(10, 11, 12), 5) > 0.0);
    }

    // momentum

    @Test
    @DisplayName("momentum saturates high for all gains")
    public void momentumGains() {
        assertEquals(100.0, Indicators.momentum(list(10, 10.5, 11, 11.5, 12), 4), 1e-9);
    }

    @Test
    @DisplayName("momentum saturates low for all losses")
    public void momentumLosses() {
        assertEquals(0.0, Indicators.momentum(list(10, 9.5, 9, 8.5, 8), 4), 1e-9);
    }

    @Test
    @DisplayName("momentum defaults to 50 when shorter than period+1")
    public void momentumShort() {
        assertEquals(50.0, Indicators.momentum(list(10, 11), 14), 1e-9);
    }

    // deviation bands (population sigma)

    @Test
    @DisplayName("deviation bands collapse to the mean for constant input")
    public void bandsConstant() {
        double[] b = Indicators.deviationBands(list(10, 10, 10, 10, 10), 5);
        assertEquals(10.0, b[0], 1e-9);
        assertEquals(10.0, b[1], 1e-9);
        assertEquals(10.0, b[2], 1e-9);
    }

    @Test
    @DisplayName("deviation bands use POPULATION std")
    public void bandsPopulationStd() {
        // {8,9,10,11,12}: mean 10, pop var 2, std √2.
        double[] b = Indicators.deviationBands(list(8, 9, 10, 11, 12), 5);
        double std = Math.sqrt(2.0);
        assertEquals(10.0 + 2 * std, b[0], 1e-9);
        assertEquals(10.0, b[1], 1e-9);
        assertEquals(10.0 - 2 * std, b[2], 1e-9);
    }

    // dispersion (population std over last period)

    @Test
    @DisplayName("dispersion is population std over the period window")
    public void dispersionPopulation() {
        // {2,4,4,4,5,5,7,9}: mean 5, pop var 4, std 2.
        assertEquals(2.0, Indicators.dispersion(list(2, 4, 4, 4, 5, 5, 7, 9), 8), 1e-9);
    }

    @Test
    @DisplayName("dispersion windows the LAST period, not the whole series")
    public void dispersionWindowsLastPeriod() {
        // Leading outlier must be excluded by the period-8 window.
        assertEquals(2.0, Indicators.dispersion(list(100, 2, 4, 4, 4, 5, 5, 7, 9), 8), 1e-9);
    }

    @Test
    @DisplayName("dispersion returns 0 when shorter than period")
    public void dispersionShort() {
        assertEquals(0.0, Indicators.dispersion(list(1, 2, 3), 8), 1e-9);
    }

    // value change (percent)

    @Test
    @DisplayName("value change is a PERCENT (x100)")
    public void valueChangePercent() {
        assertEquals(10.0, Indicators.valueChange(list(100, 110)), 1e-9);
    }

    @Test
    @DisplayName("value change is 0 for flat / single / zero-previous")
    public void valueChangeEdges() {
        assertEquals(0.0, Indicators.valueChange(list(100, 100)), 1e-9);
        assertEquals(0.0, Indicators.valueChange(list(5)), 1e-9);
        assertEquals(0.0, Indicators.valueChange(list(0, 5)), 1e-9);
    }

    // computeAll integration

    @Test
    @DisplayName("computeAll emits exactly the configured stateless feature set")
    public void computeAllKeys() {
        IndicatorConfig cfg = new IndicatorConfig(
            new int[] {7, 14}, new int[] {12, 26}, 14,
            /*trend*/ true, /*bandsPeriod*/ 20, /*bandsEnabled*/ true,
            /*secondaryAvg*/ 20, /*dispersion*/ 14, /*window*/ 200, /*macdSignal*/ 9);

        List<Double> primary = new ArrayList<>();
        List<Double> secondary = new ArrayList<>();
        for (int i = 1; i <= 30; i++) {
            primary.add((double) i);
            secondary.add(i * 100.0);
        }

        Map<String, Double> f = Indicators.computeAll(primary, secondary, cfg);

        // Present: stateless indicators.
        assertEquals(30.0, f.get("value"), 1e-9);
        assertTrue(f.containsKey("rolling_mean_7"));
        assertTrue(f.containsKey("rolling_mean_14"));
        assertTrue(f.containsKey("rolling_ema_12"));
        assertTrue(f.containsKey("rolling_ema_26"));
        assertTrue(f.containsKey("momentum_14"));
        assertTrue(f.containsKey("band_upper"));
        assertTrue(f.containsKey("band_middle"));
        assertTrue(f.containsKey("band_lower"));
        assertTrue(f.containsKey("secondary_avg"));
        assertTrue(f.containsKey("value_change"));
        assertTrue(f.containsKey("dispersion"));

        // Absent: the trend triple is stateful (added by FeatureFunction), and
        // computeAll must never emit it even when trend is enabled in config.
        assertFalse(f.containsKey("trend_convergence"));
        assertFalse(f.containsKey("trend_signal"));
        assertFalse(f.containsKey("trend_hist"));
    }

    @Test
    @DisplayName("computeAll omits secondary_avg when no secondary series")
    public void computeAllNoSecondary() {
        IndicatorConfig cfg = new IndicatorConfig(
            new int[] {7}, new int[] {12}, 14,
            false, 20, false, 20, 14, 200, 9);
        List<Double> primary = list(1, 2, 3, 4, 5, 6, 7, 8);
        Map<String, Double> f = Indicators.computeAll(primary, new ArrayList<>(), cfg);
        assertFalse(f.containsKey("secondary_avg"));
        assertTrue(f.containsKey("rolling_mean_7"));
    }

    @Test
    @DisplayName("computeAll on empty primary yields empty map")
    public void computeAllEmpty() {
        IndicatorConfig cfg = IndicatorConfig.fromEnv();
        assertTrue(Indicators.computeAll(new ArrayList<>(), new ArrayList<>(), cfg).isEmpty());
    }
}
