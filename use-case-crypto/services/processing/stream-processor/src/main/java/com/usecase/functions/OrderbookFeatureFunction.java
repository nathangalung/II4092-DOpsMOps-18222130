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
 * Computes L2 orderbook microstructure features: bid-ask spread,
 * spread volatility, depth imbalance, bid/ask depth ratio.
 *
 * Input topic is declared by {@code STREAM_ORDERBOOK_TOPIC}; function
 * class by {@code STREAM_ORDERBOOK_FUNCTION=com.usecase.functions.OrderbookFeatureFunction}.
 */
public class OrderbookFeatureFunction extends KeyedProcessFunction<String, String, String> {
    private static final Logger LOG = LoggerFactory.getLogger(OrderbookFeatureFunction.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final int windowSize;
    private final int minSnapshots;

    private transient ListState<Double> spreadHistory;
    private transient ListState<Double> bidDepthHistory;
    private transient ListState<Double> askDepthHistory;

    public OrderbookFeatureFunction() {
        this.windowSize = Integer.parseInt(
            System.getenv().getOrDefault("FLINK_ORDERBOOK_WINDOW_SIZE", "50"));
        this.minSnapshots = Integer.parseInt(
            System.getenv().getOrDefault("FLINK_ORDERBOOK_MIN_SNAPSHOTS", "5"));
    }

    @Override
    public void open(OpenContext openContext) throws Exception {
        spreadHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("ob_spreads", Types.DOUBLE));
        bidDepthHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("ob_bid_depth", Types.DOUBLE));
        askDepthHistory = getRuntimeContext().getListState(
            new ListStateDescriptor<>("ob_ask_depth", Types.DOUBLE));
    }

    @Override
    public void processElement(String value, Context ctx, Collector<String> out) throws Exception {
        JsonNode input = MAPPER.readTree(value);

        String symbol = input.get("symbol").asText();
        long timestamp = input.get("timestamp").asLong();

        double bestBid = 0, bestAsk = 0, bidDepth = 0, askDepth = 0;

        if (input.has("best_bid")) bestBid = input.get("best_bid").asDouble();
        if (input.has("best_ask")) bestAsk = input.get("best_ask").asDouble();
        if (input.has("bid_changes")) bidDepth = input.get("bid_changes").asDouble();
        if (input.has("ask_changes")) askDepth = input.get("ask_changes").asDouble();

        if (bestBid == 0 && input.has("bid")) bestBid = input.get("bid").asDouble();
        if (bestAsk == 0 && input.has("ask")) bestAsk = input.get("ask").asDouble();

        double spread = (bestAsk > 0 && bestBid > 0) ? bestAsk - bestBid : 0;

        List<Double> spreads = toList(spreadHistory.get());
        List<Double> bidDepths = toList(bidDepthHistory.get());
        List<Double> askDepths = toList(askDepthHistory.get());

        spreads.add(spread);
        bidDepths.add(bidDepth);
        askDepths.add(askDepth);

        if (spreads.size() > windowSize) {
            spreads = spreads.subList(spreads.size() - windowSize, spreads.size());
            bidDepths = bidDepths.subList(bidDepths.size() - windowSize, bidDepths.size());
            askDepths = askDepths.subList(askDepths.size() - windowSize, askDepths.size());
        }

        spreadHistory.update(spreads);
        bidDepthHistory.update(bidDepths);
        askDepthHistory.update(askDepths);

        if (spreads.size() >= minSnapshots) {
            ObjectNode features = MAPPER.createObjectNode();
            features.put("symbol", symbol);
            features.put("timestamp", timestamp);
            features.put("feature_type", "orderbook");

            features.put("spread", spread);

            double avgSpread = spreads.stream().mapToDouble(d -> d).average().orElse(0);
            features.put("avg_spread", avgSpread);

            double spreadMean = avgSpread;
            double spreadVar = spreads.stream()
                .mapToDouble(s -> (s - spreadMean) * (s - spreadMean))
                .average().orElse(0);
            features.put("spread_volatility", Math.sqrt(spreadVar));

            double totalBidDepth = bidDepths.stream().mapToDouble(d -> d).sum();
            double totalAskDepth = askDepths.stream().mapToDouble(d -> d).sum();
            double totalDepth = totalBidDepth + totalAskDepth;
            features.put("depth_imbalance",
                totalDepth > 0 ? (totalBidDepth - totalAskDepth) / totalDepth : 0);

            features.put("total_depth", totalDepth);

            features.put("bid_ask_ratio",
                totalAskDepth > 0 ? totalBidDepth / totalAskDepth : 1.0);

            out.collect(MAPPER.writeValueAsString(features));
        }
    }

    private List<Double> toList(Iterable<Double> iter) {
        List<Double> list = new ArrayList<>();
        iter.forEach(list::add);
        return list;
    }
}
