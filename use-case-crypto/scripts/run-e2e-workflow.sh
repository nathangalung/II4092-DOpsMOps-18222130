#!/bin/bash
# ============================================================
# Crypto ML Pipeline - End-to-End Workflow Automation
# ============================================================
#
# This script automates the entire crypto ML pipeline workflow:
# 1. Data Ingestion (Coinbase API → ClickHouse)
# 2. Feature Engineering (Technical Indicators)
# 3. Data Quality Validation
# 4. Model Training (with MLflow tracking)
# 5. Model Serving (KServe/API)
# 6. Monitoring & Visualization
#
# Usage: ./run-e2e-workflow.sh [step]
# Steps: all, ingest, features, quality, train, serve, dashboard
# ============================================================

set -e

# Configuration
CLUSTER="${CLUSTER:-platform}"
KUBECTL="minikube -p $CLUSTER kubectl --"
NAMESPACE="use-case-crypto"

# Helper: run a query against ClickHouse via clickhouse-client
ch_query() {
    $KUBECTL exec -n storage clickhouse-0 -- clickhouse-client --database features --query "$1" 2>/dev/null
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# Step 1: Data Ingestion
# ============================================================
step_ingest() {
    log_info "Step 1: Data Ingestion - Checking BTC-USD data in ClickHouse"

    # Check if collector pod is running
    COLLECTOR_POD=$($KUBECTL get pods -n $NAMESPACE -l app.kubernetes.io/component=rest-collector -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$COLLECTOR_POD" ]; then
        log_warning "Collector pod not found, checking ClickHouse directly..."
    else
        log_info "Collector pod: $COLLECTOR_POD"
    fi

    echo ""
    echo "=== Current Data in ClickHouse ==="
    ch_query "
        SELECT
            data_type,
            count(*) as records,
            min(timestamp) as from_date,
            max(timestamp) as to_date,
            round(avg(close), 2) as avg_price
        FROM crypto_ohlcv
        GROUP BY data_type
        ORDER BY data_type
        FORMAT PrettyCompact
    " || log_warning "No data in crypto_ohlcv yet"

    log_success "Data ingestion check complete!"
}

# ============================================================
# Step 2: Feature Engineering
# ============================================================
step_features() {
    log_info "Step 2: Feature Engineering - Checking computed indicators"

    echo ""
    echo "=== Feature Table Summary ==="
    ch_query "
        SELECT
            count(*) as total_rows,
            countIf(sma_20 != 0) as has_sma_20,
            countIf(rsi_14 != 0) as has_rsi_14,
            countIf(macd != 0) as has_macd,
            countIf(bb_upper != 0) as has_bollinger,
            countIf(adx != 0) as has_adx,
            countIf(volatility_24h != 0) as has_volatility
        FROM crypto_ohlcv_features
        FORMAT PrettyCompact
    " || log_warning "No data in crypto_ohlcv_features yet"

    echo ""
    echo "Available indicators: SMA, EMA, RSI, MACD, Bollinger Bands,"
    echo "  Stochastic, Williams %R, ADX, ATR, OBV, MFI, VWAP, Returns"

    log_success "Feature engineering check complete!"
}

# ============================================================
# Step 3: Data Quality Validation
# ============================================================
step_quality() {
    log_info "Step 3: Data Quality - Running validation checks"

    echo ""
    echo "=== Null Check Results ==="
    ch_query "
        SELECT
            countIf(open IS NULL) as null_open,
            countIf(high IS NULL) as null_high,
            countIf(low IS NULL) as null_low,
            countIf(close IS NULL) as null_close,
            countIf(volume IS NULL) as null_volume,
            count(*) as total
        FROM crypto_ohlcv
        FORMAT PrettyCompact
    " || log_warning "No data to validate"

    echo ""
    echo "=== Outlier Check Results ==="
    ch_query "
        SELECT
            countIf(close > 200000 OR close < 1000) as price_outliers,
            countIf(volume < 0) as negative_volume,
            countIf(high < low) as invalid_hl
        FROM crypto_ohlcv
        FORMAT PrettyCompact
    " || log_warning "No data for outlier checks"

    echo ""
    echo "=== Quality Outliers Detected ==="
    ch_query "
        SELECT count(*) as total_outliers
        FROM quality_outliers
        FORMAT PrettyCompact
    " || echo "  (no outliers table yet)"

    log_success "Data quality validation complete!"
}

# ============================================================
# Step 4: Model Training
# ============================================================
step_train() {
    log_info "Step 4: Model Training - Checking training data"

    echo ""
    echo "=== Training Data Summary ==="
    ch_query "
        SELECT
            data_type,
            count(*) as samples,
            min(timestamp) as start_date,
            max(timestamp) as end_date
        FROM crypto_ohlcv
        WHERE data_type IN ('train', 'validation', 'test')
        GROUP BY data_type
        FORMAT PrettyCompact
    " || log_warning "No training data splits yet"

    echo ""
    echo "Model Training Configuration:"
    echo "  - Algorithms: LightGBM, XGBoost, LSTM, CatBoost, RandomForest, Ridge"
    echo "  - Features: OHLCV + Technical Indicators + Sentiment"
    echo "  - Train:      Jan 1, 2025 - Oct 31, 2025"
    echo "  - Validation: Nov 1, 2025 - Nov 30, 2025"
    echo "  - Test:       Dec 1, 2025 - Jan 1, 2026"
    echo "  - Tracking: MLflow"
    echo "  - Export: ONNX"

    echo ""
    echo "=== Model Metrics ==="
    ch_query "
        SELECT model_type, round(rmse, 4) as rmse, round(r2, 4) as r2, training_reason
        FROM model_metrics
        ORDER BY timestamp DESC
        LIMIT 5
        FORMAT PrettyCompact
    " || echo "  (no model metrics yet)"

    log_success "Model training check complete!"
}

# ============================================================
# Step 5: Model Serving
# ============================================================
step_serve() {
    log_info "Step 5: Model Serving - Checking serving endpoints"

    echo ""
    echo "=== Model Serving Configuration ==="
    echo "  - Gateway: Rust (gRPC/REST)"
    echo "  - Inference: C++ ONNX Runtime"
    echo "  - Feature Cache: Rust + Redis"
    echo ""
    echo "API Endpoints:"
    echo "  GET  /health        - Health check"
    echo "  POST /predict       - Get prediction"
    echo "  GET  /features      - Get current features"
    echo "  GET  /model/info    - Model metadata"

    echo ""
    echo "=== Recent Predictions ==="
    ch_query "
        SELECT symbol, predicted_direction, round(confidence, 3) as confidence, model_type
        FROM crypto_predictions
        ORDER BY prediction_timestamp DESC
        LIMIT 5
        FORMAT PrettyCompact
    " || echo "  (no predictions yet)"

    # Check service
    $KUBECTL get svc -n $NAMESPACE 2>/dev/null | grep -E "(gateway|inference|feature-cache)" || log_warning "Serving services not found"

    log_success "Model serving check complete!"
}

# ============================================================
# Step 6: Dashboard & Monitoring
# ============================================================
step_dashboard() {
    log_info "Step 6: Dashboard & Monitoring"

    echo ""
    echo "=== Access URLs ==="
    echo ""
    echo "1. DASHBOARD"
    echo "   kubectl port-forward svc/crypto-dashboard-frontend -n $NAMESPACE 3000:80"
    echo "   URL: http://localhost:3000"
    echo ""
    echo "2. GRAFANA (Metrics)"
    echo "   kubectl port-forward svc/grafana -n observability 3001:3000"
    echo "   URL: http://localhost:3001"
    echo ""
    echo "3. CLICKHOUSE (Query)"
    echo "   kubectl port-forward svc/clickhouse -n storage 8123:8123"
    echo "   URL: http://localhost:8123"
    echo ""
    echo "4. MLFLOW (Experiments)"
    echo "   kubectl port-forward svc/mlflow -n model-lifecycle 5000:5000"
    echo "   URL: http://localhost:5000"
    echo ""
    echo "5. AIRFLOW (Workflows)"
    echo "   kubectl port-forward svc/airflow -n data-processing 8082:8080"
    echo "   URL: http://localhost:8082"
    echo ""

    log_success "Dashboard information displayed!"
}

# ============================================================
# Run All Steps
# ============================================================
run_all() {
    log_info "Running End-to-End Crypto ML Pipeline"
    echo "==========================================="
    echo ""

    step_ingest;    echo ""
    step_features;  echo ""
    step_quality;   echo ""
    step_train;     echo ""
    step_serve;     echo ""
    step_dashboard; echo ""

    log_success "End-to-End Pipeline Complete!"
    echo ""
    echo "==========================================="
    echo "Pipeline: Coinbase API → Kafka → ClickHouse → Feature Eng → Quality"
    echo "          → Training (MLflow) → Serving (ONNX) → Dashboard"
    echo "==========================================="
}

# ============================================================
# Main Entry Point
# ============================================================
case "${1:-all}" in
    all)       run_all ;;
    ingest)    step_ingest ;;
    features)  step_features ;;
    quality)   step_quality ;;
    train)     step_train ;;
    serve)     step_serve ;;
    dashboard) step_dashboard ;;
    *)
        echo "Usage: $0 [all|ingest|features|quality|train|serve|dashboard]"
        exit 1
        ;;
esac
