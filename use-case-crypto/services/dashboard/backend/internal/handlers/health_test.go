package handlers

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHealth(t *testing.T) {
	t.Run("returns healthy status", func(t *testing.T) {
		app := fiber.New()
		app.Get("/health", Health())

		req, _ := http.NewRequest("GET", "/health", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)
	})

	t.Run("returns correct response structure", func(t *testing.T) {
		app := fiber.New()
		app.Get("/health", Health())

		req, _ := http.NewRequest("GET", "/health", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)

		var body map[string]interface{}
		err = json.NewDecoder(resp.Body).Decode(&body)
		require.NoError(t, err)

		assert.Equal(t, "healthy", body["status"])
		assert.Contains(t, body, "latency_us")
		assert.Contains(t, body, "timestamp")
	})

	t.Run("latency is non-negative", func(t *testing.T) {
		app := fiber.New()
		app.Get("/health", Health())

		req, _ := http.NewRequest("GET", "/health", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)

		var body map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&body)

		latency := body["latency_us"].(float64)
		assert.GreaterOrEqual(t, latency, 0.0)
	})

	t.Run("timestamp is valid RFC3339 format", func(t *testing.T) {
		app := fiber.New()
		app.Get("/health", Health())

		req, _ := http.NewRequest("GET", "/health", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)

		var body map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&body)

		timestamp := body["timestamp"].(string)
		assert.NotEmpty(t, timestamp)
		assert.Contains(t, timestamp, "T")
	})

	t.Run("content type is JSON", func(t *testing.T) {
		app := fiber.New()
		app.Get("/health", Health())

		req, _ := http.NewRequest("GET", "/health", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
	})
}
