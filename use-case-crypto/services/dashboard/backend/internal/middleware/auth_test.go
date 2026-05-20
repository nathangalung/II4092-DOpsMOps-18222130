package middleware

import (
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/auth"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestAuth(t *testing.T) {
	jwtHandler := auth.NewJWT("test-secret", 24*time.Hour)

	t.Run("accepts valid bearer token", func(t *testing.T) {
		token, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			username := c.Locals("username").(string)
			role := c.Locals("role").(string)
			return c.JSON(fiber.Map{
				"username": username,
				"role":     role,
			})
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer "+token)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("rejects missing authorization header", func(t *testing.T) {
		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("rejects invalid authorization format", func(t *testing.T) {
		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		testCases := []string{
			"InvalidFormat",
			"Bearer",
			"Basic token123",
			"token123",
		}

		for _, authHeader := range testCases {
			req := httptest.NewRequest("GET", "/test", nil)
			req.Header.Set("Authorization", authHeader)

			resp, err := app.Test(req)

			require.NoError(t, err)
			assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode,
				"should reject authorization header: %s", authHeader)
		}
	})

	t.Run("rejects invalid token", func(t *testing.T) {
		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer invalid.token.here")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("rejects expired token", func(t *testing.T) {
		expiredJWT := auth.NewJWT("test-secret", -1*time.Hour)
		token, err := expiredJWT.Generate("testuser", "admin")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer "+token)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("sets username and role in context", func(t *testing.T) {
		token, err := jwtHandler.Generate("johndoe", "data_scientist")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			username, ok := c.Locals("username").(string)
			assert.True(t, ok)
			assert.Equal(t, "johndoe", username)

			role, ok := c.Locals("role").(string)
			assert.True(t, ok)
			assert.Equal(t, "data_scientist", role)

			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer "+token)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})
}

func TestRequirePermission(t *testing.T) {
	rbac := auth.NewRBAC()

	t.Run("allows access with correct permission", func(t *testing.T) {
		app := fiber.New()
		app.Use(func(c *fiber.Ctx) error {
			c.Locals("role", "data_engineer")
			return c.Next()
		})
		app.Use(RequirePermission(rbac, "ingestion:read"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("denies access without permission", func(t *testing.T) {
		app := fiber.New()
		app.Use(func(c *fiber.Ctx) error {
			c.Locals("role", "business_user")
			return c.Next()
		})
		app.Use(RequirePermission(rbac, "ingestion:write"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
	})

	t.Run("denies access when role not in context", func(t *testing.T) {
		app := fiber.New()
		app.Use(RequirePermission(rbac, "any:permission"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
	})

	t.Run("handles wildcard permissions", func(t *testing.T) {
		app := fiber.New()
		app.Use(func(c *fiber.Ctx) error {
			c.Locals("role", "data_scientist")
			return c.Next()
		})
		app.Use(RequirePermission(rbac, "features:write"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("different roles have different access", func(t *testing.T) {
		testCases := []struct {
			role       string
			permission string
			expected   int
		}{
			{"data_engineer", "ingestion:write", fiber.StatusOK},
			{"data_scientist", "ingestion:write", fiber.StatusForbidden},
			{"ml_engineer", "serving:read", fiber.StatusOK},
			{"business_user", "serving:read", fiber.StatusForbidden},
		}

		for _, tc := range testCases {
			app := fiber.New()
			app.Use(func(c *fiber.Ctx) error {
				c.Locals("role", tc.role)
				return c.Next()
			})
			app.Use(RequirePermission(rbac, tc.permission))
			app.Get("/test", func(c *fiber.Ctx) error {
				return c.SendString("success")
			})

			req := httptest.NewRequest("GET", "/test", nil)
			resp, err := app.Test(req)

			require.NoError(t, err)
			assert.Equal(t, tc.expected, resp.StatusCode,
				"role %s with permission %s should return %d", tc.role, tc.permission, tc.expected)
		}
	})
}

func TestAuthMiddleware_Integration(t *testing.T) {
	t.Run("full auth flow with permission check", func(t *testing.T) {
		jwtHandler := auth.NewJWT("test-secret", 24*time.Hour)
		rbac := auth.NewRBAC()

		// Generate token for data_engineer
		token, err := jwtHandler.Generate("engineer1", "data_engineer")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Use(RequirePermission(rbac, "ingestion:write"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.JSON(fiber.Map{
				"username": c.Locals("username"),
				"role":     c.Locals("role"),
			})
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer "+token)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusOK, resp.StatusCode)
	})

	t.Run("rejects user without permission", func(t *testing.T) {
		jwtHandler := auth.NewJWT("test-secret", 24*time.Hour)
		rbac := auth.NewRBAC()

		// Generate token for business_user (no write permissions)
		token, err := jwtHandler.Generate("viewer1", "business_user")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Use(RequirePermission(rbac, "ingestion:write"))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer "+token)

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, fiber.StatusForbidden, resp.StatusCode)
	})
}

func TestAuthMiddleware_EdgeCases(t *testing.T) {
	jwtHandler := auth.NewJWT("test-secret", 24*time.Hour)

	t.Run("handles authorization header with extra spaces", func(t *testing.T) {
		token, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "Bearer  "+token) // Extra space

		resp, err := app.Test(req)

		require.NoError(t, err)
		// Should be rejected due to extra space
		assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("handles case-sensitive Bearer keyword", func(t *testing.T) {
		token, err := jwtHandler.Generate("testuser", "admin")
		require.NoError(t, err)

		app := fiber.New()
		app.Use(Auth(jwtHandler))
		app.Get("/test", func(c *fiber.Ctx) error {
			return c.SendString("success")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		req.Header.Set("Authorization", "bearer "+token) // lowercase

		resp, err := app.Test(req)

		require.NoError(t, err)
		// Should be rejected as it's case-sensitive
		assert.Equal(t, fiber.StatusUnauthorized, resp.StatusCode)
	})
}
