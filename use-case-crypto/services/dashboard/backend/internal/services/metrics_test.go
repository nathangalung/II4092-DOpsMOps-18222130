package services

import (
	"context"
	"testing"

	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/stretchr/testify/assert"
)

func TestNewMetricsService(t *testing.T) {
	t.Run("creates service with config", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "mlops",
			},
		}

		svc := NewMetricsService(cfg)

		assert.NotNil(t, svc)
	})
}

func TestMetricsService_List(t *testing.T) {
	t.Run("returns default summary", func(t *testing.T) {
		svc := &MetricsService{db: nil}

		metrics, err := svc.List(context.Background())

		assert.NoError(t, err)
		assert.NotNil(t, metrics)
		assert.Contains(t, metrics, "total_predictions")
		assert.Contains(t, metrics, "drift_events")
		assert.Contains(t, metrics, "models_active")
		assert.Contains(t, metrics, "avg_accuracy")
	})
}

func TestMetricsService_Drift(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &MetricsService{db: nil}

		metrics, err := svc.Drift(context.Background(), "daily")

		assert.NoError(t, err)
		assert.Empty(t, metrics)
	})

	t.Run("handles different scales", func(t *testing.T) {
		svc := &MetricsService{db: nil}

		scales := []string{"daily", "hourly", "weekly"}

		for _, scale := range scales {
			metrics, err := svc.Drift(context.Background(), scale)

			assert.NoError(t, err)
			assert.Empty(t, metrics)
		}
	})
}

func TestMetricsService_Performance(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &MetricsService{db: nil}

		metrics, err := svc.Performance(context.Background(), "")

		assert.NoError(t, err)
		assert.Empty(t, metrics)
	})

	t.Run("handles model filter", func(t *testing.T) {
		svc := &MetricsService{db: nil}

		metrics, err := svc.Performance(context.Background(), "model1")

		assert.NoError(t, err)
		assert.Empty(t, metrics)
	})
}

func TestDriftMetric_Structure(t *testing.T) {
	t.Run("drift metric has correct fields", func(t *testing.T) {
		m := DriftMetric{
			Feature:     "value",
			PSI:         0.15,
			KSStatistic: 0.08,
			KSPValue:    0.05,
			IsDrifted:   true,
		}

		assert.Equal(t, "value", m.Feature)
		assert.Equal(t, 0.15, m.PSI)
		assert.Equal(t, 0.08, m.KSStatistic)
		assert.Equal(t, 0.05, m.KSPValue)
		assert.True(t, m.IsDrifted)
	})
}

func TestPerformanceMetric_Structure(t *testing.T) {
	t.Run("performance metric has correct fields", func(t *testing.T) {
		m := PerformanceMetric{
			ModelName:    "lstm-v1",
			ModelVersion: "1.0",
			Accuracy:     0.92,
			Precision:    0.90,
			Recall:       0.88,
			F1Score:      0.89,
			MAE:          0.05,
			RMSE:         0.08,
		}

		assert.Equal(t, "lstm-v1", m.ModelName)
		assert.Equal(t, "1.0", m.ModelVersion)
		assert.Equal(t, 0.92, m.Accuracy)
		assert.Equal(t, 0.90, m.Precision)
		assert.Equal(t, 0.88, m.Recall)
		assert.Equal(t, 0.89, m.F1Score)
		assert.Equal(t, 0.05, m.MAE)
		assert.Equal(t, 0.08, m.RMSE)
	})
}
