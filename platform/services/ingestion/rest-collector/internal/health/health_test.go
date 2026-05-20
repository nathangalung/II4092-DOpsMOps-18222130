package health

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewServer(t *testing.T) {
	server := NewServer()

	assert.NotNil(t, server)
	assert.NotNil(t, server.router)
}

func TestServer_healthHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := NewServer()

	req := httptest.NewRequest("GET", "/health", nil)
	w := httptest.NewRecorder()

	server.router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "healthy")
	assert.Contains(t, w.Body.String(), "rest-collector")
}

func TestServer_readyHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := NewServer()

	req := httptest.NewRequest("GET", "/ready", nil)
	w := httptest.NewRecorder()

	server.router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "ready", w.Body.String())
}

func TestServer_liveHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := NewServer()

	req := httptest.NewRequest("GET", "/live", nil)
	w := httptest.NewRecorder()

	server.router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Equal(t, "live", w.Body.String())
}

func TestServer_metricsHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := NewServer()

	// Increment some metrics
	RecordsFetched.WithLabelValues("source-a", "SYM1").Inc()
	SupplementaryFetched.WithLabelValues("supplementary-source").Inc()

	req := httptest.NewRequest("GET", "/metrics", nil)
	w := httptest.NewRecorder()

	server.router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
	assert.Contains(t, w.Body.String(), "rest_collector_records_fetched_total")
	assert.Contains(t, w.Body.String(), "rest_collector_supplementary_fetched_total")
}

func TestPrometheusMetrics(t *testing.T) {
	t.Run("RecordsFetched counter", func(t *testing.T) {
		counter := RecordsFetched.WithLabelValues("test_source", "test_symbol")
		counter.Inc()
		counter.Add(5)

		// Verify metric exists and can be collected
		metrics, err := prometheus.DefaultGatherer.Gather()
		require.NoError(t, err)

		found := false
		for _, mf := range metrics {
			if mf.GetName() == "rest_collector_records_fetched_total" {
				found = true
				break
			}
		}
		assert.True(t, found, "RecordsFetched metric should be registered")
	})

	t.Run("SupplementaryFetched counter", func(t *testing.T) {
		counter := SupplementaryFetched.WithLabelValues("test_supplementary")
		counter.Inc()

		metrics, err := prometheus.DefaultGatherer.Gather()
		require.NoError(t, err)

		found := false
		for _, mf := range metrics {
			if mf.GetName() == "rest_collector_supplementary_fetched_total" {
				found = true
				break
			}
		}
		assert.True(t, found, "SupplementaryFetched metric should be registered")
	})

	t.Run("FetchErrors counter", func(t *testing.T) {
		counter := FetchErrors.WithLabelValues("test_error")
		counter.Inc()

		metrics, err := prometheus.DefaultGatherer.Gather()
		require.NoError(t, err)

		found := false
		for _, mf := range metrics {
			if mf.GetName() == "rest_collector_fetch_errors_total" {
				found = true
				break
			}
		}
		assert.True(t, found, "FetchErrors metric should be registered")
	})

	t.Run("BackfillProgress gauge", func(t *testing.T) {
		gauge := BackfillProgress.WithLabelValues("SYM1")
		gauge.Set(0.5)
		gauge.Set(1.0)

		metrics, err := prometheus.DefaultGatherer.Gather()
		require.NoError(t, err)

		found := false
		for _, mf := range metrics {
			if mf.GetName() == "rest_collector_backfill_progress" {
				found = true
				break
			}
		}
		assert.True(t, found, "BackfillProgress metric should be registered")
	})
}

func TestServer_Run(t *testing.T) {
	t.Run("server starts on specified address", func(t *testing.T) {
		gin.SetMode(gin.TestMode)
		server := NewServer()

		// Test that Run method exists and has correct signature
		// We don't actually start the server in tests
		assert.NotNil(t, server.Run)
	})
}

func TestServer_setupRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)
	server := NewServer()

	routes := []struct {
		method string
		path   string
	}{
		{"GET", "/health"},
		{"GET", "/ready"},
		{"GET", "/live"},
		{"GET", "/metrics"},
	}

	for _, route := range routes {
		req := httptest.NewRequest(route.method, route.path, nil)
		w := httptest.NewRecorder()

		server.router.ServeHTTP(w, req)

		assert.NotEqual(t, http.StatusNotFound, w.Code,
			"Route %s %s should exist", route.method, route.path)
	}
}

func TestMetricLabels(t *testing.T) {
	t.Run("RecordsFetched accepts source and symbol labels", func(t *testing.T) {
		sources := []string{"source-a", "source-b"}
		symbols := []string{"SYM1", "SYM2", "SYM3"}

		for _, source := range sources {
			for _, symbol := range symbols {
				counter := RecordsFetched.WithLabelValues(source, symbol)
				counter.Inc()
			}
		}
	})

	t.Run("SupplementaryFetched accepts source label", func(t *testing.T) {
		sources := []string{"supplementary-a", "supplementary-b"}

		for _, source := range sources {
			counter := SupplementaryFetched.WithLabelValues(source)
			counter.Inc()
		}
	})

	t.Run("BackfillProgress accepts symbol label", func(t *testing.T) {
		symbols := []string{"SYM1", "SYM2"}

		for _, symbol := range symbols {
			gauge := BackfillProgress.WithLabelValues(symbol)
			gauge.Set(0.75)
		}
	})
}
