// Features handlers.
package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/services"
)

// FeaturesHandler handles feature endpoints.
type FeaturesHandler struct {
	svc *services.FeatureService
}

// NewFeaturesHandler creates features handler.
func NewFeaturesHandler(svc *services.FeatureService) *FeaturesHandler {
	return &FeaturesHandler{svc: svc}
}

// List returns all features.
func (h *FeaturesHandler) List(c *fiber.Ctx) error {
	symbol := c.Query("symbol", "")

	features, err := h.svc.List(c.Context(), symbol)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(features)
}

// Get returns feature by name.
func (h *FeaturesHandler) Get(c *fiber.Ctx) error {
	name := c.Params("name")
	symbol := c.Query("symbol", "")

	feature, err := h.svc.Get(c.Context(), name, symbol)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": err.Error(),
		})
	}

	return c.JSON(feature)
}
