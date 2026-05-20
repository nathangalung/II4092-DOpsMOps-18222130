package services

import (
	"context"
	"testing"

	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/stretchr/testify/assert"
)

func TestNewPredictionService(t *testing.T) {
	t.Run("creates service with config", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "mlops",
			},
		}

		svc := NewPredictionService(cfg)

		assert.NotNil(t, svc)
		// DB will be nil if ClickHouse is not running, which is expected in tests
	})

	t.Run("handles invalid connection", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "invalid-host",
				Port:     9999,
				Database: "test",
			},
		}

		svc := NewPredictionService(cfg)

		// Should create service even if connection fails
		assert.NotNil(t, svc)
	})
}

func TestPredictionService_List(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &PredictionService{db: nil}

		predictions, err := svc.List(context.Background(), 10, 0)

		assert.NoError(t, err)
		assert.Empty(t, predictions)
	})

	t.Run("validates limit and offset parameters", func(t *testing.T) {
		svc := &PredictionService{db: nil}

		// Should not panic with large values
		predictions, err := svc.List(context.Background(), 1000, 5000)

		assert.NoError(t, err)
		assert.Empty(t, predictions)
	})
}

func TestPredictionService_Latest(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &PredictionService{db: nil}

		predictions, err := svc.Latest(context.Background())

		assert.NoError(t, err)
		assert.Empty(t, predictions)
	})
}

func TestPredictionService_BySymbol(t *testing.T) {
	t.Run("returns empty when db is nil", func(t *testing.T) {
		svc := &PredictionService{db: nil}

		predictions, err := svc.BySymbol(context.Background(), "SYMBOL-1", 10)

		assert.NoError(t, err)
		assert.Empty(t, predictions)
	})

	t.Run("validates symbol parameter", func(t *testing.T) {
		svc := &PredictionService{db: nil}

		// Should handle various symbol formats
		symbols := []string{"SYMBOL-1", "SYMBOL-2", "ENTITY-ABC", ""}

		for _, symbol := range symbols {
			predictions, err := svc.BySymbol(context.Background(), symbol, 10)

			assert.NoError(t, err)
			assert.Empty(t, predictions)
		}
	})
}

func TestScanPredictions(t *testing.T) {
	t.Run("handles nil rows", func(t *testing.T) {
		predictions, err := scanPredictions(nil)

		// Should handle gracefully
		assert.Nil(t, predictions)
		assert.Error(t, err)
	})
}

func TestPrediction_Structure(t *testing.T) {
	t.Run("prediction struct has correct fields", func(t *testing.T) {
		p := Prediction{
			ID:             "pred-1",
			Symbol:         "SYMBOL-1",
			CurrentValue:   100.0,
			PredictedValue: 102.0,
			ClassLabel:     "CLASS_0",
			Confidence:     0.85,
			ModelVersion:   "v1",
		}

		assert.Equal(t, "pred-1", p.ID)
		assert.Equal(t, "SYMBOL-1", p.Symbol)
		assert.Equal(t, 100.0, p.CurrentValue)
		assert.Equal(t, 102.0, p.PredictedValue)
		assert.Equal(t, "CLASS_0", p.ClassLabel)
		assert.Equal(t, 0.85, p.Confidence)
		assert.Equal(t, "v1", p.ModelVersion)
	})
}
