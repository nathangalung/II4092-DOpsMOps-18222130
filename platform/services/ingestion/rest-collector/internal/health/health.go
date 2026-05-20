// Package health provides health check and metrics endpoints
package health

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	// RecordsFetched counts total records fetched from APIs
	RecordsFetched = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rest_collector_records_fetched_total",
			Help: "Total records fetched from data source APIs",
		},
		[]string{"source", "symbol"},
	)

	// SupplementaryFetched counts supplementary/alternative records
	SupplementaryFetched = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rest_collector_supplementary_fetched_total",
			Help: "Total supplementary records fetched",
		},
		[]string{"source"},
	)

	// FetchErrors counts fetch errors
	FetchErrors = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "rest_collector_fetch_errors_total",
			Help: "Total fetch errors by source",
		},
		[]string{"source"},
	)

	// BackfillProgress tracks backfill completion
	BackfillProgress = prometheus.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "rest_collector_backfill_progress",
			Help: "Backfill progress by symbol (0-1)",
		},
		[]string{"symbol"},
	)
)

func init() {
	prometheus.MustRegister(RecordsFetched)
	prometheus.MustRegister(SupplementaryFetched)
	prometheus.MustRegister(FetchErrors)
	prometheus.MustRegister(BackfillProgress)
}

// Server provides health and metrics endpoints
type Server struct {
	router *gin.Engine
}

// NewServer creates a health server
func NewServer() *Server {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())

	s := &Server{router: r}
	s.setupRoutes()
	return s
}

func (s *Server) setupRoutes() {
	s.router.GET("/health", s.healthHandler)
	s.router.GET("/ready", s.readyHandler)
	s.router.GET("/live", s.liveHandler)
	s.router.GET("/metrics", gin.WrapH(promhttp.Handler()))
}

func (s *Server) healthHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"service": "rest-collector",
	})
}

func (s *Server) readyHandler(c *gin.Context) {
	c.String(http.StatusOK, "ready")
}

func (s *Server) liveHandler(c *gin.Context) {
	c.String(http.StatusOK, "live")
}

// Run starts the health server
func (s *Server) Run(addr string) error {
	return s.router.Run(addr)
}
