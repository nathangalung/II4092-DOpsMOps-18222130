// Metrics handlers.
package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/services"
)

// MetricsHandler handles metrics endpoints.
type MetricsHandler struct {
	svc *services.MetricsService
}

// NewMetricsHandler creates metrics handler.
func NewMetricsHandler(svc *services.MetricsService) *MetricsHandler {
	return &MetricsHandler{svc: svc}
}

// List returns all metrics.
func (h *MetricsHandler) List(c *fiber.Ctx) error {
	metrics, err := h.svc.List(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(metrics)
}

// Drift returns drift metrics.
func (h *MetricsHandler) Drift(c *fiber.Ctx) error {
	scale := c.Query("scale", "daily")

	metrics, err := h.svc.Drift(c.Context(), scale)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(metrics)
}

// Performance returns model performance.
func (h *MetricsHandler) Performance(c *fiber.Ctx) error {
	model := c.Query("model", "")

	metrics, err := h.svc.Performance(c.Context(), model)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(metrics)
}
