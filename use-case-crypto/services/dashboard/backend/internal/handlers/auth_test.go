package handlers

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/auth"
	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

// MockJWT is a mock for auth.JWT
type MockJWT struct {
	mock.Mock
}

func (m *MockJWT) Generate(userID, role string) (string, error) {
	args := m.Called(userID, role)
	return args.String(0), args.Error(1)
}

func (m *MockJWT) Validate(token string) (*auth.Claims, error) {
	args := m.Called(token)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*auth.Claims), args.Error(1)
}

func createTestConfig() *config.Config {
	return &config.Config{
		Auth: config.AuthConfig{
			JWTSecret: "test-secret",
			Users: []config.UserConfig{
				{Username: "admin", Password: "password", Role: "admin"},
				{Username: "user", Password: "userpass", Role: "viewer"},
			},
		},
	}
}

func TestAuthHandler_Login(t *testing.T) {
	t.Run("successful login returns token", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/login", handler.Login)

		body := `{"username": "admin", "password": "password"}`
		req := httptest.NewRequest("POST", "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var result LoginResponse
		json.NewDecoder(resp.Body).Decode(&result)
		assert.NotEmpty(t, result.Token)
		assert.Equal(t, "admin", result.Username)
		assert.Equal(t, "admin", result.Role)
	})

	t.Run("invalid credentials returns 401", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/login", handler.Login)

		body := `{"username": "admin", "password": "wrongpassword"}`
		req := httptest.NewRequest("POST", "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Equal(t, "invalid credentials", result["error"])
	})

	t.Run("invalid request body returns 400", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/login", handler.Login)

		body := `invalid json`
		req := httptest.NewRequest("POST", "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 400, resp.StatusCode)
	})

	t.Run("unknown user returns 401", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/login", handler.Login)

		body := `{"username": "unknown", "password": "password"}`
		req := httptest.NewRequest("POST", "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 401, resp.StatusCode)
	})

	t.Run("viewer role login works", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/login", handler.Login)

		body := `{"username": "user", "password": "userpass"}`
		req := httptest.NewRequest("POST", "/login", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")

		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var result LoginResponse
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Equal(t, "viewer", result.Role)
	})
}

func TestAuthHandler_Logout(t *testing.T) {
	t.Run("logout returns success message", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Post("/logout", handler.Logout)

		req := httptest.NewRequest("POST", "/logout", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Equal(t, "logged out", result["message"])
	})
}

func TestAuthHandler_Me(t *testing.T) {
	t.Run("returns current user info", func(t *testing.T) {
		cfg := createTestConfig()
		jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, 24*time.Hour)
		handler := NewAuthHandler(cfg, jwtAuth)

		app := fiber.New()
		app.Get("/me", func(c *fiber.Ctx) error {
			c.Locals("username", "testuser")
			c.Locals("role", "admin")
			return handler.Me(c)
		})

		req := httptest.NewRequest("GET", "/me", nil)
		resp, err := app.Test(req)

		require.NoError(t, err)
		assert.Equal(t, 200, resp.StatusCode)

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		assert.Equal(t, "testuser", result["username"])
		assert.Equal(t, "admin", result["role"])
	})
}

func TestLoginRequest(t *testing.T) {
	t.Run("struct fields", func(t *testing.T) {
		req := LoginRequest{
			Username: "test",
			Password: "pass",
		}
		assert.Equal(t, "test", req.Username)
		assert.Equal(t, "pass", req.Password)
	})
}

func TestLoginResponse(t *testing.T) {
	t.Run("struct fields", func(t *testing.T) {
		resp := LoginResponse{
			Token:    "token123",
			Username: "user",
			Role:     "admin",
		}
		assert.Equal(t, "token123", resp.Token)
		assert.Equal(t, "user", resp.Username)
		assert.Equal(t, "admin", resp.Role)
	})
}
