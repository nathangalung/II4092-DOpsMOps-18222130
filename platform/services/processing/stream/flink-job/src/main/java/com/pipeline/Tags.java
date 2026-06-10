package com.pipeline;

import org.apache.flink.util.OutputTag;

/**
 * Shared Flink {@link OutputTag}s used to fan a single keyed function's output
 * into multiple sinks without re-computing features.
 *
 * <p>{@link #CACHE_TAG} carries the <em>online-cache projection</em>: the bare
 * indicator map ({@code {feature: number}}) destined for the low-latency
 * Valkey serving cache under {@code features:{symbol}}. The function's main
 * output carries the full feature record (passthrough input + indicators)
 * destined for the durable Kafka → ClickHouse bronze path. Splitting at the
 * function (rather than re-deriving downstream) keeps the two projections in
 * lock-step and lets each sink own its own delivery guarantee.
 */
public final class Tags {
    private Tags() {}

    /** Online-cache side output: indicator-only JSON for the Valkey serving cache. */
    public static final OutputTag<String> CACHE_TAG = new OutputTag<String>("online-cache") {};
}
