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

func TestNewPredictionsHandler(t *testing.T) {
	t.Run("creates handler successfully", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		assert.NotNil(t, handler)
		assert.NotNil(t, handler.svc)
	})
}

func TestPredictionsHandler_List(t *testing.T) {
	t.Run("returns predictions with default pagination", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		app := fiber.New()
		app.Get("/predictions", handler.List)

		req := httptest.NewRequest("GET", "/predictions", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.Prediction
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})

	t.Run("accepts limit and offset query parameters", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		app := fiber.New()
		app.Get("/predictions", handler.List)

		req := httptest.NewRequest("GET", "/predictions?limit=50&offset=10", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestPredictionsHandler_Latest(t *testing.T) {
	t.Run("returns latest predictions", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		app := fiber.New()
		app.Get("/predictions/latest", handler.Latest)

		req := httptest.NewRequest("GET", "/predictions/latest", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.Prediction
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})
}

func TestPredictionsHandler_BySymbol(t *testing.T) {
	t.Run("returns predictions for specific symbol", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		app := fiber.New()
		app.Get("/predictions/:symbol", handler.BySymbol)

		req := httptest.NewRequest("GET", "/predictions/SYMBOL-1", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.Prediction
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotNil(t, result)
	})

	t.Run("accepts limit query parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewPredictionService(cfg)
		handler := NewPredictionsHandler(svc)

		app := fiber.New()
		app.Get("/predictions/:symbol", handler.BySymbol)

		req := httptest.NewRequest("GET", "/predictions/SYMBOL-2?limit=50", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestPrediction_StructureHandler(t *testing.T) {
	t.Run("has correct fields", func(t *testing.T) {
		prediction := services.Prediction{
			Symbol:         "SYMBOL-1",
			ModelVersion:   "lstm_v1",
			PredictedValue: 51000.0,
			Confidence:     0.85,
			CurrentValue:   50500.0,
			ClassLabel:     "CLASS_0",
		}

		assert.Equal(t, "SYMBOL-1", prediction.Symbol)
		assert.Equal(t, "lstm_v1", prediction.ModelVersion)
		assert.Equal(t, 51000.0, prediction.PredictedValue)
		assert.Equal(t, 0.85, prediction.Confidence)
		assert.Equal(t, 50500.0, prediction.CurrentValue)
		assert.Equal(t, "CLASS_0", prediction.ClassLabel)
	})
}
