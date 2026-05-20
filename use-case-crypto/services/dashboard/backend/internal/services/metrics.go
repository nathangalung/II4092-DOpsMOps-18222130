// Metrics service for monitoring data.
package services

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"time"

	"github.com/mlops-platform/dashboard/internal/config"
)

// DriftMetric represents drift detection result.
type DriftMetric struct {
	Timestamp   time.Time `json:"timestamp"`
	Scale       string    `json:"scale"`
	Feature     string    `json:"feature"`
	PSI         float64   `json:"psi"`
	KSStatistic float64   `json:"ks_statistic"`
	KSPValue    float64   `json:"ks_pvalue"`
	IsDrifted   bool      `json:"is_drifted"`
}

// PerformanceMetric represents model performance.
type PerformanceMetric struct {
	Timestamp    time.Time `json:"timestamp"`
	ModelName    string    `json:"model_name"`
	ModelVersion string    `json:"model_version"`
	Accuracy     float64   `json:"accuracy"`
	Precision    float64   `json:"precision"`
	Recall       float64   `json:"recall"`
	F1Score      float64   `json:"f1_score"`
	MAE          float64   `json:"mae"`
	RMSE         float64   `json:"rmse"`
}

// MetricsService handles metrics queries.
type MetricsService struct {
	db         *sql.DB
	driftTable string
	perfTable  string
}

// NewMetricsService creates metrics service.
func NewMetricsService(cfg *config.Config) *MetricsService {
	dsn := fmt.Sprintf("clickhouse://%s:%d/%s",
		cfg.ClickHouse.Host, cfg.ClickHouse.Port, cfg.ClickHouse.Database)

	driftTable := os.Getenv("DRIFT_METRICS_TABLE")
	if driftTable == "" {
		driftTable = "drift_metrics"
	}
	perfTable := os.Getenv("MODEL_PERFORMANCE_TABLE")
	if perfTable == "" {
		perfTable = "model_performance"
	}

	db, err := sql.Open("clickhouse", dsn)
	if err != nil {
		return &MetricsService{driftTable: driftTable, perfTable: perfTable}
	}

	if err := db.Ping(); err != nil {
		db.Close()
		return &MetricsService{driftTable: driftTable, perfTable: perfTable}
	}

	return &MetricsService{db: db, driftTable: driftTable, perfTable: perfTable}
}

// List returns summary metrics.
func (s *MetricsService) List(ctx context.Context) (map[string]interface{}, error) {
	return map[string]interface{}{
		"total_predictions": 0,
		"drift_events":      0,
		"models_active":     0,
		"avg_accuracy":      0.0,
	}, nil
}

// Drift returns drift metrics by scale.
func (s *MetricsService) Drift(ctx context.Context, scale string) ([]DriftMetric, error) {
	if s.db == nil {
		return []DriftMetric{}, nil
	}

	query := fmt.Sprintf(`
		SELECT timestamp, scale, feature, psi, ks_statistic, ks_pvalue, is_drifted
		FROM %s
		WHERE scale = ?
		ORDER BY timestamp DESC
		LIMIT 100
	`, s.driftTable)

	rows, err := s.db.QueryContext(ctx, query, scale)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var metrics []DriftMetric
	for rows.Next() {
		var m DriftMetric
		err := rows.Scan(&m.Timestamp, &m.Scale, &m.Feature, &m.PSI, &m.KSStatistic, &m.KSPValue, &m.IsDrifted)
		if err != nil {
			continue
		}
		metrics = append(metrics, m)
	}

	return metrics, nil
}

// Performance returns model performance metrics.
func (s *MetricsService) Performance(ctx context.Context, model string) ([]PerformanceMetric, error) {
	if s.db == nil {
		return []PerformanceMetric{}, nil
	}

	query := fmt.Sprintf(`
		SELECT timestamp, model_name, model_version, accuracy, precision, recall, f1_score, mae, rmse
		FROM %s
		ORDER BY timestamp DESC
		LIMIT 100
	`, s.perfTable)

	if model != "" {
		query = fmt.Sprintf(`
			SELECT timestamp, model_name, model_version, accuracy, precision, recall, f1_score, mae, rmse
			FROM %s
			WHERE model_name = ?
			ORDER BY timestamp DESC
			LIMIT 100
		`, s.perfTable)
	}

	var rows *sql.Rows
	var err error
	if model != "" {
		rows, err = s.db.QueryContext(ctx, query, model)
	} else {
		rows, err = s.db.QueryContext(ctx, query)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var metrics []PerformanceMetric
	for rows.Next() {
		var m PerformanceMetric
		err := rows.Scan(&m.Timestamp, &m.ModelName, &m.ModelVersion, &m.Accuracy, &m.Precision, &m.Recall, &m.F1Score, &m.MAE, &m.RMSE)
		if err != nil {
			continue
		}
		metrics = append(metrics, m)
	}

	return metrics, nil
}
