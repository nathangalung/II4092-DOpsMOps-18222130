package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestModelsHandler_List(t *testing.T) {
	t.Run("returns registered models", func(t *testing.T) {
		// Create mock MLflow server
		mlflowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "/api/2.0/mlflow/registered-models/list", r.URL.Path)
			response := map[string]interface{}{
				"registered_models": []map[string]interface{}{
					{"name": "model1", "latest_version": "v1"},
					{"name": "model2", "latest_version": "v2"},
				},
			}
			json.NewEncoder(w).Encode(response)
		}))
		defer mlflowServer.Close()

		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = mlflowServer.URL

		app := fiber.New()
		app.Get("/models", handler.List)

		req := httptest.NewRequest("GET", "/models", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Contains(t, result, "registered_models")
	})

	t.Run("handles MLflow unavailability", func(t *testing.T) {
		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = "http://localhost:1"

		app := fiber.New()
		app.Get("/models", handler.List)

		req := httptest.NewRequest("GET", "/models", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusServiceUnavailable, resp.StatusCode)
	})
}

func TestModelsHandler_Get(t *testing.T) {
	t.Run("returns model details", func(t *testing.T) {
		mlflowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Contains(t, r.URL.Path, "/api/2.0/mlflow/registered-models/get")
			assert.Equal(t, "test-model", r.URL.Query().Get("name"))
			response := map[string]interface{}{
				"registered_model": map[string]interface{}{
					"name":        "test-model",
					"description": "Test model",
				},
			}
			json.NewEncoder(w).Encode(response)
		}))
		defer mlflowServer.Close()

		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = mlflowServer.URL

		app := fiber.New()
		app.Get("/models/:name", handler.Get)

		req := httptest.NewRequest("GET", "/models/test-model", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("handles MLflow error", func(t *testing.T) {
		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = "http://localhost:1"

		app := fiber.New()
		app.Get("/models/:name", handler.Get)

		req := httptest.NewRequest("GET", "/models/test-model", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusServiceUnavailable, resp.StatusCode)
	})
}

func TestModelsHandler_Versions(t *testing.T) {
	t.Run("returns model versions", func(t *testing.T) {
		mlflowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			response := map[string]interface{}{
				"registered_model": map[string]interface{}{
					"name": "test-model",
					"latest_versions": []map[string]interface{}{
						{"version": "1", "stage": "Production"},
						{"version": "2", "stage": "Staging"},
					},
				},
			}
			json.NewEncoder(w).Encode(response)
		}))
		defer mlflowServer.Close()

		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = mlflowServer.URL

		app := fiber.New()
		app.Get("/models/:name/versions", handler.Versions)

		req := httptest.NewRequest("GET", "/models/test-model/versions", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Contains(t, result, "versions")
	})

	t.Run("returns empty array when no versions", func(t *testing.T) {
		mlflowServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			response := map[string]interface{}{
				"registered_model": map[string]interface{}{
					"name": "test-model",
				},
			}
			json.NewEncoder(w).Encode(response)
		}))
		defer mlflowServer.Close()

		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = mlflowServer.URL

		app := fiber.New()
		app.Get("/models/:name/versions", handler.Versions)

		req := httptest.NewRequest("GET", "/models/test-model/versions", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("handles MLflow error", func(t *testing.T) {
		cfg := &config.Config{}
		handler := NewModelsHandler(cfg)
		handler.mlflowURL = "http://localhost:1"

		app := fiber.New()
		app.Get("/models/:name/versions", handler.Versions)

		req := httptest.NewRequest("GET", "/models/test-model/versions", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusServiceUnavailable, resp.StatusCode)
	})
}

func TestNewModelsHandler(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)

	handler := NewModelsHandler(cfg)

	assert.NotNil(t, handler)
	assert.Equal(t, "http://mlflow.model-lifecycle.svc.cluster.local:5000", handler.mlflowURL)
}
