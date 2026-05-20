// Auth middleware for JWT validation.
package middleware

import (
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/auth"
)

// Auth validates JWT token.
func Auth(jwt *auth.JWT) fiber.Handler {
	return func(c *fiber.Ctx) error {
		header := c.Get("Authorization")
		if header == "" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "missing authorization header",
			})
		}

		parts := strings.SplitN(header, " ", 2)
		if len(parts) != 2 || parts[0] != "Bearer" {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "invalid authorization format",
			})
		}

		claims, err := jwt.Validate(parts[1])
		if err != nil {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "invalid token",
			})
		}

		c.Locals("username", claims.Username)
		c.Locals("role", claims.Role)

		return c.Next()
	}
}

// RequirePermission checks RBAC permission.
func RequirePermission(rbac *auth.RBAC, permission string) fiber.Handler {
	return func(c *fiber.Ctx) error {
		role, ok := c.Locals("role").(string)
		if !ok {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error": "role not found",
			})
		}

		if !rbac.HasPermission(role, permission) {
			return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
				"error": "permission denied",
			})
		}

		return c.Next()
	}
}
