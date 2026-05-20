"""
Feast feature definitions for crypto pipeline.
Includes OHLCV, technical indicators, and sentiment features.
Uses modern Feast SDK API (0.40+) with ClickHouse source and Redis online store.
"""

from datetime import timedelta
from feast import Entity, FeatureView, Field, PushSource, FeatureService
from feast.types import Float64, Int32
from feast.infra.offline_stores.contrib.clickhouse_offline_store.clickhouse_source import (
    ClickhouseSource,
)

# =============================================================================
# Entity Definitions
# =============================================================================

crypto_entity = Entity(
    name="symbol",
    join_keys=["symbol"],
    description="Cryptocurrency trading pair (e.g., BTC-USD, ETH-USD)",
)

# =============================================================================
# Source Definitions
# =============================================================================

# OHLCV data source (uses database from feature_store.yaml offline_store config)
ohlcv_source = ClickhouseSource(
    name="ohlcv_source",
    table="crypto_ohlcv",
    timestamp_field="timestamp",
    created_timestamp_column="created_at",
)

# Features data source (OHLCV + technical indicators)
features_source = ClickhouseSource(
    name="features_source",
    table="crypto_ohlcv_features",
    timestamp_field="timestamp",
    created_timestamp_column="created_at",
)

# Sentiment features source
sentiment_source = ClickhouseSource(
    name="sentiment_source",
    table="crypto_sentiment_features",
    timestamp_field="timestamp",
    created_timestamp_column="created_at",
)

# Push source for real-time features
realtime_push_source = PushSource(
    name="crypto_realtime_push",
    batch_source=ohlcv_source,
)

# =============================================================================
# Feature Views - OHLCV
# =============================================================================

ohlcv_fv = FeatureView(
    name="ohlcv",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="open", dtype=Float64, description="Opening price"),
        Field(name="high", dtype=Float64, description="Highest price"),
        Field(name="low", dtype=Float64, description="Lowest price"),
        Field(name="close", dtype=Float64, description="Closing price"),
        Field(name="volume", dtype=Float64, description="Trading volume"),
    ],
    source=ohlcv_source,
    online=True,
    tags={"layer": "raw", "data_type": "ohlcv"},
)

# =============================================================================
# Feature Views - Technical Indicators
# =============================================================================

moving_averages_fv = FeatureView(
    name="moving_averages",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="sma_20", dtype=Float64, description="20-period SMA"),
        Field(name="sma_50", dtype=Float64, description="50-period SMA"),
        Field(name="ema_12", dtype=Float64, description="12-period EMA"),
        Field(name="ema_26", dtype=Float64, description="26-period EMA"),
    ],
    source=features_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "trend"},
)

momentum_indicators_fv = FeatureView(
    name="momentum_indicators",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="rsi_14", dtype=Float64, description="14-period RSI"),
        Field(name="rsi_7", dtype=Float64, description="7-period RSI"),
        Field(name="macd", dtype=Float64, description="MACD line"),
        Field(name="macd_signal", dtype=Float64, description="MACD signal line"),
        Field(name="stoch_k", dtype=Float64, description="Stochastic %K"),
        Field(name="stoch_d", dtype=Float64, description="Stochastic %D"),
        Field(name="williams_r", dtype=Float64, description="Williams %R"),
        Field(name="roc_10", dtype=Float64, description="Rate of Change"),
    ],
    source=features_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "momentum"},
)

volatility_indicators_fv = FeatureView(
    name="volatility_indicators",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="bb_upper", dtype=Float64, description="Bollinger upper band"),
        Field(name="bb_lower", dtype=Float64, description="Bollinger lower band"),
        Field(name="bb_width", dtype=Float64, description="Bollinger band width"),
        Field(name="atr_14", dtype=Float64, description="Average True Range"),
        Field(name="volatility_24h", dtype=Float64, description="24h volatility"),
    ],
    source=features_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "volatility"},
)

volume_indicators_fv = FeatureView(
    name="volume_indicators",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="obv", dtype=Float64, description="On-Balance Volume"),
        Field(name="mfi_14", dtype=Float64, description="Money Flow Index"),
        Field(name="vwap", dtype=Float64, description="Volume Weighted Avg Price"),
    ],
    source=features_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "volume"},
)

returns_fv = FeatureView(
    name="returns",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="return_1h", dtype=Float64, description="1-hour return"),
        Field(name="return_24h", dtype=Float64, description="24-hour return"),
        Field(name="adx", dtype=Float64, description="Average Directional Index"),
    ],
    source=features_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "trend"},
)

# =============================================================================
# Feature Views - Sentiment (from news/embeddings)
# =============================================================================

sentiment_1h_fv = FeatureView(
    name="sentiment_1h",
    entities=[crypto_entity],
    ttl=timedelta(hours=2),
    schema=[
        Field(name="news_count", dtype=Int32, description="News articles count (1h)"),
        Field(
            name="avg_sentiment",
            dtype=Float64,
            description="Average sentiment score (1h)",
        ),
        Field(
            name="sentiment_std",
            dtype=Float64,
            description="Sentiment std deviation (1h)",
        ),
        Field(
            name="positive_ratio", dtype=Float64, description="Positive news ratio (1h)"
        ),
        Field(
            name="sentiment_momentum",
            dtype=Float64,
            description="Sentiment change (1h)",
        ),
    ],
    source=sentiment_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "sentiment", "window": "1h"},
)

sentiment_6h_fv = FeatureView(
    name="sentiment_6h",
    entities=[crypto_entity],
    ttl=timedelta(hours=8),
    schema=[
        Field(name="news_count", dtype=Int32, description="News articles count (6h)"),
        Field(
            name="avg_sentiment",
            dtype=Float64,
            description="Average sentiment score (6h)",
        ),
        Field(
            name="sentiment_std",
            dtype=Float64,
            description="Sentiment std deviation (6h)",
        ),
        Field(
            name="positive_ratio", dtype=Float64, description="Positive news ratio (6h)"
        ),
        Field(
            name="sentiment_momentum",
            dtype=Float64,
            description="Sentiment change (6h)",
        ),
    ],
    source=sentiment_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "sentiment", "window": "6h"},
)

sentiment_24h_fv = FeatureView(
    name="sentiment_24h",
    entities=[crypto_entity],
    ttl=timedelta(days=1),
    schema=[
        Field(name="news_count", dtype=Int32, description="News articles count (24h)"),
        Field(
            name="avg_sentiment",
            dtype=Float64,
            description="Average sentiment score (24h)",
        ),
        Field(
            name="sentiment_std",
            dtype=Float64,
            description="Sentiment std deviation (24h)",
        ),
        Field(
            name="positive_ratio",
            dtype=Float64,
            description="Positive news ratio (24h)",
        ),
        Field(
            name="sentiment_momentum",
            dtype=Float64,
            description="Sentiment change (24h)",
        ),
    ],
    source=sentiment_source,
    online=True,
    tags={"layer": "feature", "indicator_type": "sentiment", "window": "24h"},
)

# =============================================================================
# Feature Services
# =============================================================================

# Full feature service for training (includes sentiment)
training_feature_service = FeatureService(
    name="crypto_training_features",
    features=[
        ohlcv_fv,
        moving_averages_fv,
        momentum_indicators_fv,
        volatility_indicators_fv,
        volume_indicators_fv,
        returns_fv,
        sentiment_1h_fv,
        sentiment_6h_fv,
        sentiment_24h_fv,
    ],
    tags={"purpose": "training", "includes_sentiment": "true"},
)

# Real-time inference (optimized for latency)
inference_feature_service = FeatureService(
    name="crypto_inference_features",
    features=[
        ohlcv_fv[["close", "volume"]],
        momentum_indicators_fv[["rsi_14", "macd"]],
        volatility_indicators_fv[["bb_upper", "bb_lower", "atr_14"]],
        returns_fv[["return_1h"]],
        sentiment_1h_fv[["avg_sentiment", "news_count"]],
        sentiment_24h_fv[["avg_sentiment", "sentiment_momentum"]],
    ],
    tags={"purpose": "inference", "latency_optimized": "true"},
)

# Technical-only (for models without sentiment)
technical_feature_service = FeatureService(
    name="crypto_technical_features",
    features=[
        ohlcv_fv,
        moving_averages_fv,
        momentum_indicators_fv,
        volatility_indicators_fv,
        volume_indicators_fv,
        returns_fv,
    ],
    tags={"purpose": "training", "includes_sentiment": "false"},
)
