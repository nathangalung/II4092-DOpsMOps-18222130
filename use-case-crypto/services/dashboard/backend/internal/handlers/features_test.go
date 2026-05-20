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

func TestNewFeaturesHandler(t *testing.T) {
	t.Run("creates handler successfully", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		assert.NotNil(t, handler)
		assert.NotNil(t, handler.svc)
	})
}

func TestFeaturesHandler_List(t *testing.T) {
	t.Run("returns feature definitions", func(t *testing.T) {
		t.Setenv("FEATURE_DEFINITIONS", "price:Current price:float64,volume:Trade volume:float64")

		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		app := fiber.New()
		app.Get("/features", handler.List)

		req := httptest.NewRequest("GET", "/features", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.FeatureDefinition
		json.NewDecoder(resp.Body).Decode(&result)

		// Should return predefined feature list
		assert.Greater(t, len(result), 0)

		// Verify features have correct structure
		for _, f := range result {
			assert.NotEmpty(t, f.Name)
			assert.NotEmpty(t, f.Type)
		}
	})

	t.Run("accepts symbol query parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		app := fiber.New()
		app.Get("/features", handler.List)

		req := httptest.NewRequest("GET", "/features?symbol=SYMBOL-1", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestFeaturesHandler_Get(t *testing.T) {
	t.Run("handles get request without database", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		app := fiber.New()
		app.Get("/features/:name", handler.Get)

		req := httptest.NewRequest("GET", "/features/value_1?symbol=SYMBOL-1", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		// Will return 200 with empty array when no DB connection
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result []services.Feature
		json.NewDecoder(resp.Body).Decode(&result)
		// Without real DB, should return empty array
		assert.NotNil(t, result)
	})

	t.Run("accepts symbol query parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		app := fiber.New()
		app.Get("/features/:name", handler.Get)

		req := httptest.NewRequest("GET", "/features/value_2?symbol=SYMBOL-2", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("handles missing symbol parameter", func(t *testing.T) {
		cfg := &config.Config{
			ClickHouse: config.ClickHouseConfig{
				Host:     "localhost",
				Port:     9000,
				Database: "test_db",
			},
		}
		svc := services.NewFeatureService(cfg)
		handler := NewFeaturesHandler(svc)

		app := fiber.New()
		app.Get("/features/:name", handler.Get)

		req := httptest.NewRequest("GET", "/features/value_1", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestFeatureDefinition_StructureHandler(t *testing.T) {
	t.Run("has correct fields", func(t *testing.T) {
		def := services.FeatureDefinition{
			Name:        "test_feature",
			Description: "Test feature description",
			Type:        "float64",
			Tags:        []string{"test", "example"},
		}

		assert.Equal(t, "test_feature", def.Name)
		assert.Equal(t, "Test feature description", def.Description)
		assert.Equal(t, "float64", def.Type)
		assert.Len(t, def.Tags, 2)
	})
}

func TestFeature_StructureHandler(t *testing.T) {
	t.Run("has correct fields", func(t *testing.T) {
		feature := services.Feature{
			Symbol: "SYMBOL-1",
			Name:   "value_1",
			Value:  100.0,
		}

		assert.Equal(t, "SYMBOL-1", feature.Symbol)
		assert.Equal(t, "value_1", feature.Name)
		assert.Equal(t, 100.0, feature.Value)
	})
}
