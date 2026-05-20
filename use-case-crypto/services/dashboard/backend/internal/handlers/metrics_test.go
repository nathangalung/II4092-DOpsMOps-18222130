package handlers

import (
	"encoding/json"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/mlops-platform/dashboard/internal/services"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewMetricsHandler(t *testing.T) {
	t.Run("creates handler successfully", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		assert.NotNil(t, handler)
		assert.NotNil(t, handler.svc)
	})
}

func TestMetricsHandler_List(t *testing.T) {
	t.Run("returns metrics summary", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		app := fiber.New()
		app.Get("/metrics", handler.List)

		req := httptest.NewRequest("GET", "/metrics", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		// Will return 200 even without DB connection (returns empty/default data)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})
}

func TestMetricsHandler_Drift(t *testing.T) {
	t.Run("returns drift metrics with default scale", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		app := fiber.New()
		app.Get("/metrics/drift", handler.Drift)

		req := httptest.NewRequest("GET", "/metrics/drift", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.DriftMetric
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})

	t.Run("accepts scale query parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		app := fiber.New()
		app.Get("/metrics/drift", handler.Drift)

		req := httptest.NewRequest("GET", "/metrics/drift?scale=hourly", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestMetricsHandler_Performance(t *testing.T) {
	t.Run("returns performance metrics", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		app := fiber.New()
		app.Get("/metrics/performance", handler.Performance)

		req := httptest.NewRequest("GET", "/metrics/performance", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.PerformanceMetric
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})

	t.Run("accepts model query parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewMetricsService(cfg)
		handler := NewMetricsHandler(svc)

		app := fiber.New()
		app.Get("/metrics/performance", handler.Performance)

		req := httptest.NewRequest("GET", "/metrics/performance?model=lstm_v1", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestDriftMetric_StructureHandler(t *testing.T) {
	t.Run("has correct fields", func(t *testing.T) {
		metric := services.DriftMetric{
			Feature:     "value_1",
			PSI:         0.85,
			KSStatistic: 0.5,
			IsDrifted:   true,
		}

		assert.Equal(t, "value_1", metric.Feature)
		assert.Equal(t, 0.85, metric.PSI)
		assert.Equal(t, 0.5, metric.KSStatistic)
		assert.True(t, metric.IsDrifted)
	})
}

func TestPerformanceMetric_StructureHandler(t *testing.T) {
	t.Run("has correct fields", func(t *testing.T) {
		metric := services.PerformanceMetric{
			ModelName: "lstm_v1",
			Accuracy:  0.92,
			RMSE:      0.05,
			MAE:       0.03,
		}

		assert.Equal(t, "lstm_v1", metric.ModelName)
		assert.Equal(t, 0.92, metric.Accuracy)
		assert.Equal(t, 0.05, metric.RMSE)
		assert.Equal(t, 0.03, metric.MAE)
	})
}
