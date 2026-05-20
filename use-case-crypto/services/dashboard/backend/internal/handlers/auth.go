// Auth handlers for login/logout.
package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/auth"
	"github.com/mlops-platform/dashboard/internal/config"
)

// AuthHandler handles authentication.
type AuthHandler struct {
	cfg *config.Config
	jwt *auth.JWT
}

// NewAuthHandler creates auth handler.
func NewAuthHandler(cfg *config.Config, jwt *auth.JWT) *AuthHandler {
	return &AuthHandler{cfg: cfg, jwt: jwt}
}

// LoginRequest for login.
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// LoginResponse for login.
type LoginResponse struct {
	Token    string `json:"token"`
	Username string `json:"username"`
	Role     string `json:"role"`
}

// Login authenticates user.
func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request",
		})
	}

	// Find user
	var user *config.UserConfig
	for _, u := range h.cfg.Auth.Users {
		if u.Username == req.Username && u.Password == req.Password {
			user = &u
			break
		}
	}

	if user == nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "invalid credentials",
		})
	}

	// Generate token
	token, err := h.jwt.Generate(user.Username, user.Role)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to generate token",
		})
	}

	return c.JSON(LoginResponse{
		Token:    token,
		Username: user.Username,
		Role:     user.Role,
	})
}

// Logout invalidates session.
func (h *AuthHandler) Logout(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message": "logged out",
	})
}

// Me returns current user info.
func (h *AuthHandler) Me(c *fiber.Ctx) error {
	username := c.Locals("username").(string)
	role := c.Locals("role").(string)

	return c.JSON(fiber.Map{
		"username": username,
		"role":     role,
	})
}
