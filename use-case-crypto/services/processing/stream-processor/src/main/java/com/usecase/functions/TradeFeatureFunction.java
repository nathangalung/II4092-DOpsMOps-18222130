package com.usecase.functions;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
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
 * Computes trade-stream features: VWAP, trade volume, buy/sell ratio,
 * price impact. Maintains per-symbol rolling state keyed by `symbol`.
 *
 * Input topic is declared by {@code STREAM_TRADES_TOPIC}; function class
 * by {@code STREAM_TRADES_FUNCTION=com.usecase.functions.TradeFeatureFunction}.
 * See use-case-crypto/manifests/base/configmaps/topics.yaml.
 */
public class TradeFeatureFunction extends KeyedProcessFunction<String, String, String> {
    private static final Logger LOG = LoggerFactory.getLogger(TradeFeatureFunction.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final int windowSize;
    private final int minTrades;

    private transient ListState<Double> priceHistory;
    private transient ListState<Double> sizeHistory;
    private transient ListState<String> sideHistory;

    public TradeFeatureFunction() {
        this.windowSize = Integer.parseInt(
            System.getenv().getOrDefault("FLINK_TRADE_WINDOW_SIZE", "100"));
        this.minTrades = Integer.parseInt(
            System.getenv().getOrDefault("FLINK_TRADE_MIN_TRADES", "10"));
    }

    @Override
    public void open(OpenContext openContext) throws Exception {
        priceHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("trade_prices", Types.DOUBLE));
        sizeHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("trade_sizes", Types.DOUBLE));
        sideHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("trade_sides", Types.STRING));
    }

    @Override
    public void processElement(String value, Context ctx, Collector<String> out) throws Exception {
        JsonNode input = MAPPER.readTree(value);

        String symbol = input.get("symbol").asText();
        double price = input.get("price").asDouble();
        double size = input.has("size") ? input.get("size").asDouble() : 0.0;
        String side = input.has("side") ? input.get("side").asText() : "unknown";
        long timestamp = input.get("timestamp").asLong();

        List<Double> prices = toList(priceHistory.get());
        List<Double> sizes = toList(sizeHistory.get());
        List<String> sides = toStringList(sideHistory.get());

        prices.add(price);
        sizes.add(size);
        sides.add(side);

        if (prices.size() > windowSize) {
            prices = prices.subList(prices.size() - windowSize, prices.size());
            sizes = sizes.subList(sizes.size() - windowSize, sizes.size());
            sides = sides.subList(sides.size() - windowSize, sides.size());
        }

        priceHistory.update(prices);
        sizeHistory.update(sizes);
        sideHistory.update(sides);

        if (prices.size() >= minTrades) {
            ObjectNode features = MAPPER.createObjectNode();
            features.put("symbol", symbol);
            features.put("timestamp", timestamp);
            features.put("feature_type", "trade");

            double totalPriceVolume = 0;
            double totalVolume = 0;
            for (int i = 0; i < prices.size(); i++) {
                totalPriceVolume += prices.get(i) * sizes.get(i);
                totalVolume += sizes.get(i);
            }
            features.put("vwap", totalVolume > 0 ? totalPriceVolume / totalVolume : price);
            features.put("trade_volume", totalVolume);
            features.put("trade_count", prices.size());

            long buyCount = sides.stream().filter(s -> "buy".equals(s)).count();
            long sellCount = sides.stream().filter(s -> "sell".equals(s)).count();
            double totalSided = buyCount + sellCount;
            features.put("buy_ratio", totalSided > 0 ? (double) buyCount / totalSided : 0.5);

            features.put("avg_trade_size", totalVolume / prices.size());

            double vwap = totalVolume > 0 ? totalPriceVolume / totalVolume : price;
            features.put("price_impact", (price - vwap) / vwap);

            out.collect(MAPPER.writeValueAsString(features));
        }
    }

    private List<Double> toList(Iterable<Double> iter) {
        List<Double> list = new ArrayList<>();
        iter.forEach(list::add);
        return list;
    }

    private List<String> toStringList(Iterable<String> iter) {
        List<String> list = new ArrayList<>();
        iter.forEach(list::add);
        return list;
    }
}
