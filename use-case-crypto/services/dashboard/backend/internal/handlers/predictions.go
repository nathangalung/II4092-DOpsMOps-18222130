// Predictions handlers.
package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/services"
)

// PredictionsHandler handles prediction endpoints.
type PredictionsHandler struct {
	svc *services.PredictionService
}

// NewPredictionsHandler creates predictions handler.
func NewPredictionsHandler(svc *services.PredictionService) *PredictionsHandler {
	return &PredictionsHandler{svc: svc}
}

// List returns all predictions.
func (h *PredictionsHandler) List(c *fiber.Ctx) error {
	limit := c.QueryInt("limit", 100)
	offset := c.QueryInt("offset", 0)

	predictions, err := h.svc.List(c.Context(), limit, offset)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(predictions)
}

// Latest returns latest predictions.
func (h *PredictionsHandler) Latest(c *fiber.Ctx) error {
	predictions, err := h.svc.Latest(c.Context())
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(predictions)
}

// BySymbol returns predictions for symbol.
func (h *PredictionsHandler) BySymbol(c *fiber.Ctx) error {
	symbol := c.Params("symbol")
	limit := c.QueryInt("limit", 100)

	predictions, err := h.svc.BySymbol(c.Context(), symbol, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(predictions)
}
