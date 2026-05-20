// Dashboard backend entry point.
package main

import (
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"

	"github.com/mlops-platform/dashboard/internal/auth"
	"github.com/mlops-platform/dashboard/internal/config"
	"github.com/mlops-platform/dashboard/internal/handlers"
	"github.com/mlops-platform/dashboard/internal/middleware"
	"github.com/mlops-platform/dashboard/internal/services"
	"github.com/mlops-platform/dashboard/internal/websocket"
)

func main() {
	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize services
	predSvc := services.NewPredictionService(cfg)
	metricsSvc := services.NewMetricsService(cfg)
	featureSvc := services.NewFeatureService(cfg)

	// Initialize auth
	jwtAuth := auth.NewJWT(cfg.Auth.JWTSecret, cfg.Auth.TokenExpiry)
	rbac := auth.NewRBAC()

	// Initialize websocket manager
	wsManager := websocket.NewManager()
	go wsManager.Run()

	// Create Fiber app
	app := fiber.New(fiber.Config{
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	})

	// Global middleware
	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(middleware.CORS())

	// Health check
	app.Get("/health", handlers.Health())

	// Auth routes
	authHandler := handlers.NewAuthHandler(cfg, jwtAuth)
	app.Post("/api/auth/login", authHandler.Login)
	app.Post("/api/auth/logout", authHandler.Logout)
	app.Get("/api/auth/me", middleware.Auth(jwtAuth), authHandler.Me)

	// API routes with auth
	api := app.Group("/api", middleware.Auth(jwtAuth))

	// Predictions
	predHandler := handlers.NewPredictionsHandler(predSvc)
	api.Get("/predictions", middleware.RequirePermission(rbac, "predictions:read"), predHandler.List)
	api.Get("/predictions/latest", middleware.RequirePermission(rbac, "predictions:read"), predHandler.Latest)
	api.Get("/predictions/:symbol", middleware.RequirePermission(rbac, "predictions:read"), predHandler.BySymbol)

	// Metrics
	metricsHandler := handlers.NewMetricsHandler(metricsSvc)
	api.Get("/metrics", middleware.RequirePermission(rbac, "monitoring:read"), metricsHandler.List)
	api.Get("/metrics/drift", middleware.RequirePermission(rbac, "monitoring:read"), metricsHandler.Drift)
	api.Get("/metrics/performance", middleware.RequirePermission(rbac, "monitoring:read"), metricsHandler.Performance)

	// Models
	modelsHandler := handlers.NewModelsHandler(cfg)
	api.Get("/models", middleware.RequirePermission(rbac, "experiments:read"), modelsHandler.List)
	api.Get("/models/:name", middleware.RequirePermission(rbac, "experiments:read"), modelsHandler.Get)
	api.Get("/models/:name/versions", middleware.RequirePermission(rbac, "experiments:read"), modelsHandler.Versions)

	// Features
	featuresHandler := handlers.NewFeaturesHandler(featureSvc)
	api.Get("/features", middleware.RequirePermission(rbac, "features:read"), featuresHandler.List)
	api.Get("/features/:name", middleware.RequirePermission(rbac, "features:read"), featuresHandler.Get)

	// WebSocket
	app.Get("/ws", middleware.Auth(jwtAuth), websocket.Handler(wsManager))

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-quit
		log.Println("Shutting down...")
		wsManager.Shutdown()
		_ = app.Shutdown()
	}()

	// Start server
	addr := ":8080"
	if cfg.Server.Port != 0 {
		addr = fmt.Sprintf(":%d", cfg.Server.Port)
	}
	log.Printf("Starting server on %s", addr)
	if err := app.Listen(addr); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
