package middleware

import (
	"net/http/httptest"
	"testing"

	"github.com/gofiber/fiber/v2"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCORS(t *testing.T) {
	t.Run("returns CORS middleware", func(t *testing.T) {
		handler := CORS()
		assert.NotNil(t, handler)
	})

	t.Run("adds CORS headers to response", func(t *testing.T) {
		app := fiber.New()
		app.Use(CORS())
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("ok")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Origin", "http://localhost:3000")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
		assert.NotEmpty(t, resp.Header.Get("Access-Control-Allow-Origin"))
	})

	t.Run("handles preflight OPTIONS request", func(t *testing.T) {
		app := fiber.New()
		app.Use(CORS())
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("ok")
		})

		req := httptest.NewRequest("OPTIONS", "/test", nil)
		req.Header.Set("Origin", "http://localhost:3000")
		req.Header.Set("Access-Control-Request-Method", "POST")
		req.Header.Set("Access-Control-Request-Headers", "Authorization")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusNoContent, resp.StatusCode)
	})

	t.Run("allows all methods", func(t *testing.T) {
		app := fiber.New()
		app.Use(CORS())
		app.All("/test", func(c *fiber.Ctx) error {
			return c.SendString("ok")
		})

		methods := []string{"GET", "POST", "PUT", "DELETE"}

		for _, method := range methods {
			req := httptest.NewRequest(method, "/test", nil)
			req.Header.Set("Origin", "http://localhost:3000")

			resp, err := app.Test(req)

			require.NoError(t, err)
			assert.Equal(t, fiber.StatusOK, resp.StatusCode,
				"should allow %s method", method)
		}
	})
}
