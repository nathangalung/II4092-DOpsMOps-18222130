// Models handlers for MLflow integration.
package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/mlops-platform/dashboard/internal/config"
)

// ModelsHandler handles model endpoints.
type ModelsHandler struct {
	mlflowURL string
	client    *http.Client
}

// NewModelsHandler creates models handler.
func NewModelsHandler(cfg *config.Config) *ModelsHandler {
	return &ModelsHandler{
		mlflowURL: cfg.MLflow.URL,
		client:    &http.Client{Timeout: 5 * time.Second},
	}
}

// Model represents MLflow model.
type Model struct {
	Name            string `json:"name"`
	LatestVersion   string `json:"latest_version"`
	Description     string `json:"description"`
	CreationTime    int64  `json:"creation_time"`
	LastUpdatedTime int64  `json:"last_updated_time"`
}

// ModelVersion represents model version.
type ModelVersion struct {
	Version     string `json:"version"`
	Stage       string `json:"stage"`
	Status      string `json:"status"`
	RunID       string `json:"run_id"`
	CreatedTime int64  `json:"created_time"`
}

// List returns all registered models.
func (h *ModelsHandler) List(c *fiber.Ctx) error {
	resp, err := h.client.Get(h.mlflowURL + "/api/2.0/mlflow/registered-models/list")
	if err != nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"error": "mlflow unavailable",
		})
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	return c.JSON(result)
}

// Get returns model details.
func (h *ModelsHandler) Get(c *fiber.Ctx) error {
	name := c.Params("name")
	url := fmt.Sprintf("%s/api/2.0/mlflow/registered-models/get?name=%s", h.mlflowURL, name)

	resp, err := h.client.Get(url)
	if err != nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"error": "mlflow unavailable",
		})
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	return c.JSON(result)
}

// Versions returns model versions.
func (h *ModelsHandler) Versions(c *fiber.Ctx) error {
	name := c.Params("name")
	url := fmt.Sprintf("%s/api/2.0/mlflow/registered-models/get?name=%s", h.mlflowURL, name)

	resp, err := h.client.Get(url)
	if err != nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"error": "mlflow unavailable",
		})
	}
	defer resp.Body.Close()

	var result map[string]interface{}
	json.NewDecoder(resp.Body).Decode(&result)

	// Extract versions from response
	if rm, ok := result["registered_model"].(map[string]interface{}); ok {
		if versions, ok := rm["latest_versions"]; ok {
			return c.JSON(fiber.Map{"versions": versions})
		}
	}

	return c.JSON(fiber.Map{"versions": []interface{}{}})
}
