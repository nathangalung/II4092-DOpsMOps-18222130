// Health check with timing.
package handlers

import (
	"time"

	"github.com/gofiber/fiber/v2"
)

// Health returns status and latency.
func Health() fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()
		latency := time.Since(start).Microseconds()
		return c.JSON(fiber.Map{
			"status":     "healthy",
			"latency_us": latency,
			"timestamp":  time.Now().UTC().Format(time.RFC3339Nano),
		})
	}
}
