#!/usr/bin/env -S uv run python
"""Feature Categories - Common and Asset-Specific Features"""

from dataclasses import dataclass
from typing import Dict, List


@dataclass
class FeatureDefinition:
    """Feature metadata"""

    name: str
    category: str
    description: str
    calculation: str
    asset_type: str  # 'common', 'stock', 'crypto'


# =============================================================================
# COMMON FEATURES (OHLCV-based)
# =============================================================================
COMMON_FEATURES: Dict[str, List[FeatureDefinition]] = {
    "price_volume": [
        FeatureDefinition("open", "price_volume", "Opening price", "Raw", "common"),
        FeatureDefinition("high", "price_volume", "Highest price", "Raw", "common"),
        FeatureDefinition("low", "price_volume", "Lowest price", "Raw", "common"),
        FeatureDefinition("close", "price_volume", "Closing price", "Raw", "common"),
        FeatureDefinition("volume", "price_volume", "Trading volume", "Raw", "common"),
    ],
    "statistical": [
        FeatureDefinition(
            "return_1h",
            "statistical",
            "Hourly return",
            "(close_t - close_{t-1}) / close_{t-1}",
            "common",
        ),
        FeatureDefinition(
            "return_4h",
            "statistical",
            "4-hour return",
            "(close_t - close_{t-4}) / close_{t-4}",
            "common",
        ),
        FeatureDefinition(
            "return_1d",
            "statistical",
            "Daily return",
            "(close_t - close_{t-24}) / close_{t-24}",
            "common",
        ),
        FeatureDefinition(
            "log_return",
            "statistical",
            "Log return",
            "ln(close_t / close_{t-1})",
            "common",
        ),
        FeatureDefinition(
            "price_range", "statistical", "High-low range", "high - low", "common"
        ),
        FeatureDefinition(
            "range_ratio",
            "statistical",
            "Range to close",
            "(high - low) / close_{t-1}",
            "common",
        ),
        FeatureDefinition(
            "volatility_N", "statistical", "Rolling std", "std(returns, N)", "common"
        ),
    ],
    "lag": [
        FeatureDefinition(
            "close_lag_N", "lag", "Price N periods ago", "close_{t-N}", "common"
        ),
        FeatureDefinition(
            "return_lag_N", "lag", "Return N periods ago", "return_{t-N}", "common"
        ),
        FeatureDefinition(
            "volume_lag_N", "lag", "Volume N periods ago", "volume_{t-N}", "common"
        ),
    ],
    "trend": [
        FeatureDefinition(
            "sma_N", "trend", "Simple moving avg", "mean(close, N)", "common"
        ),
        FeatureDefinition(
            "ema_N", "trend", "Exponential moving avg", "ewm(close, N)", "common"
        ),
        FeatureDefinition("macd", "trend", "MACD line", "ema_12 - ema_26", "common"),
        FeatureDefinition(
            "macd_signal", "trend", "MACD signal", "ema(macd, 9)", "common"
        ),
        FeatureDefinition(
            "macd_histogram", "trend", "MACD histogram", "macd - signal", "common"
        ),
        FeatureDefinition("adx", "trend", "Avg directional index", "ADX(14)", "common"),
    ],
    "momentum": [
        FeatureDefinition("rsi_N", "momentum", "Relative strength", "RSI(N)", "common"),
        FeatureDefinition(
            "stoch_k", "momentum", "Stochastic %K", "Stochastic(14,3)", "common"
        ),
        FeatureDefinition(
            "stoch_d", "momentum", "Stochastic %D", "SMA(stoch_k, 3)", "common"
        ),
        FeatureDefinition(
            "roc_N",
            "momentum",
            "Rate of change",
            "(close - close_{t-N}) / close_{t-N}",
            "common",
        ),
        FeatureDefinition(
            "williams_r", "momentum", "Williams %R", "Williams(14)", "common"
        ),
        FeatureDefinition(
            "cci_N", "momentum", "Commodity channel", "CCI(20)", "common"
        ),
    ],
    "volatility": [
        FeatureDefinition(
            "bb_upper", "volatility", "Bollinger upper", "SMA + 2*std", "common"
        ),
        FeatureDefinition(
            "bb_lower", "volatility", "Bollinger lower", "SMA - 2*std", "common"
        ),
        FeatureDefinition(
            "bb_width",
            "volatility",
            "Bollinger width",
            "(upper - lower) / middle",
            "common",
        ),
        FeatureDefinition(
            "bb_pct",
            "volatility",
            "Bollinger %B",
            "(close - lower) / (upper - lower)",
            "common",
        ),
        FeatureDefinition(
            "atr_N", "volatility", "Average true range", "ATR(N)", "common"
        ),
    ],
    "volume_indicators": [
        FeatureDefinition(
            "obv", "volume", "On-balance volume", "cumsum(sign * volume)", "common"
        ),
        FeatureDefinition("mfi_N", "volume", "Money flow index", "MFI(N)", "common"),
        FeatureDefinition(
            "vwap",
            "volume",
            "Volume weighted avg",
            "(typical * volume) / volume",
            "common",
        ),
        FeatureDefinition("ad_line", "volume", "Accum/dist line", "AD()", "common"),
        FeatureDefinition(
            "volume_sma_N", "volume", "Volume moving avg", "SMA(volume, N)", "common"
        ),
        FeatureDefinition(
            "volume_ratio",
            "volume",
            "Volume to avg",
            "volume / SMA(volume, N)",
            "common",
        ),
    ],
}


# =============================================================================
# STOCK-SPECIFIC FEATURES
# =============================================================================
STOCK_FEATURES: Dict[str, List[FeatureDefinition]] = {
    "adjusted": [
        FeatureDefinition(
            "adj_close",
            "adjusted",
            "Adjusted close",
            "Split/dividend adjusted",
            "stock",
        ),
        FeatureDefinition(
            "adj_return", "adjusted", "Adjusted return", "adj_close change", "stock"
        ),
    ],
    "fundamental": [
        FeatureDefinition(
            "pe_ratio", "fundamental", "P/E ratio", "price / earnings", "stock"
        ),
        FeatureDefinition(
            "forward_pe",
            "fundamental",
            "Forward P/E",
            "price / forward_earnings",
            "stock",
        ),
        FeatureDefinition(
            "peg_ratio", "fundamental", "PEG ratio", "pe / growth", "stock"
        ),
        FeatureDefinition(
            "price_to_book", "fundamental", "Price/Book", "price / book_value", "stock"
        ),
        FeatureDefinition(
            "dividend_yield",
            "fundamental",
            "Dividend yield",
            "dividend / price",
            "stock",
        ),
        FeatureDefinition(
            "beta",
            "fundamental",
            "Market beta",
            "covar(stock, market) / var(market)",
            "stock",
        ),
        FeatureDefinition(
            "market_cap", "fundamental", "Market cap", "price * shares", "stock"
        ),
    ],
    "market": [
        FeatureDefinition(
            "sp500_return", "market", "S&P 500 return", "^GSPC return", "stock"
        ),
        FeatureDefinition(
            "nasdaq_return", "market", "NASDAQ return", "^IXIC return", "stock"
        ),
        FeatureDefinition("vix_level", "market", "VIX index", "^VIX close", "stock"),
        FeatureDefinition(
            "sector_return", "market", "Sector return", "sector ETF return", "stock"
        ),
        FeatureDefinition(
            "relative_strength",
            "market",
            "Relative strength",
            "stock_return / market_return",
            "stock",
        ),
    ],
    "trading": [
        FeatureDefinition(
            "52w_high", "trading", "52-week high", "max(close, 252)", "stock"
        ),
        FeatureDefinition(
            "52w_low", "trading", "52-week low", "min(close, 252)", "stock"
        ),
        FeatureDefinition(
            "dist_to_52w_high",
            "trading",
            "Distance to 52w high",
            "(52w_high - close) / close",
            "stock",
        ),
        FeatureDefinition(
            "avg_volume", "trading", "Average volume", "mean(volume, 20)", "stock"
        ),
    ],
}


# =============================================================================
# CRYPTO-SPECIFIC FEATURES
# =============================================================================
CRYPTO_FEATURES: Dict[str, List[FeatureDefinition]] = {
    "market_structure": [
        FeatureDefinition(
            "bid_ask_spread",
            "market_structure",
            "Bid-ask spread",
            "ask - bid",
            "crypto",
        ),
        FeatureDefinition(
            "order_book_imbalance",
            "market_structure",
            "Order imbalance",
            "bid_vol / ask_vol",
            "crypto",
        ),
        FeatureDefinition(
            "funding_rate",
            "market_structure",
            "Perpetual funding",
            "Derivatives exchange",
            "crypto",
        ),
    ],
    "blockchain": [
        FeatureDefinition(
            "active_addresses",
            "blockchain",
            "Active addresses",
            "On-chain API",
            "crypto",
        ),
        FeatureDefinition(
            "transaction_count",
            "blockchain",
            "Transaction count",
            "On-chain API",
            "crypto",
        ),
        FeatureDefinition(
            "hash_rate", "blockchain", "Network hash rate", "Mining stats", "crypto"
        ),
        FeatureDefinition(
            "difficulty", "blockchain", "Mining difficulty", "Network stats", "crypto"
        ),
    ],
    "defi": [
        FeatureDefinition(
            "tvl", "defi", "Total value locked", "DeFi protocol data", "crypto"
        ),
        FeatureDefinition(
            "dex_volume", "defi", "DEX trading volume", "DEX aggregator", "crypto"
        ),
        FeatureDefinition(
            "staking_ratio", "defi", "Staking ratio", "staked / supply", "crypto"
        ),
    ],
    "sentiment": [
        FeatureDefinition(
            "fear_greed_index",
            "sentiment",
            "Fear & Greed",
            "alternative.me API",
            "crypto",
        ),
        FeatureDefinition(
            "social_volume",
            "sentiment",
            "Social mentions",
            "Twitter/Reddit API",
            "crypto",
        ),
        FeatureDefinition(
            "google_trends", "sentiment", "Search interest", "Google Trends", "crypto"
        ),
        FeatureDefinition(
            "news_sentiment", "sentiment", "News sentiment", "NLP on news", "crypto"
        ),
    ],
    "cross_asset": [
        FeatureDefinition(
            "btc_dominance",
            "cross_asset",
            "BTC dominance",
            "btc_cap / total_cap",
            "crypto",
        ),
        FeatureDefinition(
            "eth_btc_ratio",
            "cross_asset",
            "ETH/BTC ratio",
            "eth_price / btc_price",
            "crypto",
        ),
        FeatureDefinition(
            "correlation_btc",
            "cross_asset",
            "Correlation to BTC",
            "rolling_corr(asset, BTC)",
            "crypto",
        ),
        FeatureDefinition(
            "correlation_sp500",
            "cross_asset",
            "Correlation to S&P",
            "rolling_corr(asset, SPX)",
            "crypto",
        ),
    ],
}


# =============================================================================
# TIME-BASED FEATURES
# =============================================================================
TIME_FEATURES: Dict[str, List[FeatureDefinition]] = {
    "cyclical": [
        FeatureDefinition(
            "hour_sin", "cyclical", "Hour sine", "sin(2π * hour / 24)", "common"
        ),
        FeatureDefinition(
            "hour_cos", "cyclical", "Hour cosine", "cos(2π * hour / 24)", "common"
        ),
        FeatureDefinition(
            "day_sin", "cyclical", "Day sine", "sin(2π * day / 7)", "common"
        ),
        FeatureDefinition(
            "day_cos", "cyclical", "Day cosine", "cos(2π * day / 7)", "common"
        ),
        FeatureDefinition(
            "month_sin", "cyclical", "Month sine", "sin(2π * month / 12)", "common"
        ),
        FeatureDefinition(
            "month_cos", "cyclical", "Month cosine", "cos(2π * month / 12)", "common"
        ),
    ],
    "binary": [
        FeatureDefinition(
            "is_market_hours", "binary", "Market hours", "9AM-4PM weekdays", "stock"
        ),
        FeatureDefinition(
            "is_weekend", "binary", "Weekend", "Saturday/Sunday", "common"
        ),
        FeatureDefinition(
            "is_month_end", "binary", "Month end", "Last 3 days of month", "common"
        ),
        FeatureDefinition(
            "is_quarter_end", "binary", "Quarter end", "Last week of quarter", "stock"
        ),
    ],
}


# =============================================================================
# CANDLESTICK PATTERNS
# =============================================================================
CANDLESTICK_PATTERNS: List[FeatureDefinition] = [
    FeatureDefinition(
        "is_doji", "candlestick", "Doji pattern", "body < 10% range", "common"
    ),
    FeatureDefinition(
        "is_hammer", "candlestick", "Hammer pattern", "lower > 2*body", "common"
    ),
    FeatureDefinition(
        "is_shooting_star", "candlestick", "Shooting star", "upper > 2*body", "common"
    ),
    FeatureDefinition(
        "is_bullish_engulfing",
        "candlestick",
        "Bullish engulfing",
        "Pattern detection",
        "common",
    ),
    FeatureDefinition(
        "is_bearish_engulfing",
        "candlestick",
        "Bearish engulfing",
        "Pattern detection",
        "common",
    ),
    FeatureDefinition(
        "is_morning_star", "candlestick", "Morning star", "3-candle pattern", "common"
    ),
    FeatureDefinition(
        "is_evening_star", "candlestick", "Evening star", "3-candle pattern", "common"
    ),
]


def get_all_features(asset_type: str = "common") -> List[FeatureDefinition]:
    """Get all features for asset type"""
    features = []

    # Add common features
    for category_features in COMMON_FEATURES.values():
        features.extend(category_features)

    for category_features in TIME_FEATURES.values():
        features.extend(
            [f for f in category_features if f.asset_type in ["common", asset_type]]
        )

    features.extend(CANDLESTICK_PATTERNS)

    # Add asset-specific features
    if asset_type == "stock":
        for category_features in STOCK_FEATURES.values():
            features.extend(category_features)
    elif asset_type == "crypto":
        for category_features in CRYPTO_FEATURES.values():
            features.extend(category_features)

    return features


def get_feature_categories(asset_type: str = "common") -> Dict[str, List[str]]:
    """Get feature names grouped by category"""
    features = get_all_features(asset_type)
    categories: Dict[str, List[str]] = {}

    for f in features:
        if f.category not in categories:
            categories[f.category] = []
        categories[f.category].append(f.name)

    return categories
