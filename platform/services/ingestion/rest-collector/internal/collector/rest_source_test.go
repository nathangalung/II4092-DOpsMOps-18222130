package collector

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mlops-platform/rest-collector/config"
	"github.com/stretchr/testify/assert"
	"go.uber.org/zap"
)

func TestRESTSourceCollector_FetchHistorical(t *testing.T) {
	t.Run("successfully fetches single chunk", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			assert.Equal(t, "SAMPLE-1", r.URL.Query().Get("symbol"))
			assert.Equal(t, "60", r.URL.Query().Get("granularity"))

			// Generic format: [time, low, high, open, close, volume]
			response := `[[1600000000, "9900.0", "10100.0", "10000.5", "10050.2", "50.5"]]`
			_, _ = w.Write([]byte(response))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Enabled:     true,
			Name:        "test-source",
			BaseURL:     ts.URL,
			Symbols:     []string{"SAMPLE-1"},
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		logger := zap.NewNop()
		collector := NewRESTSourceCollector(cfg, logger)

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		records, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.Len(t, records, 1)

		c := records[0]
		assert.Equal(t, "SAMPLE-1", c.Symbol)
		assert.Equal(t, "test-source", c.Source)
		assert.Equal(t, 9900.0, c.Values["value_1"])
		assert.Equal(t, 10100.0, c.Values["value_2"])
		assert.Equal(t, 10000.5, c.Values["value_3"])
		assert.Equal(t, 10050.2, c.Values["value_4"])
		assert.Equal(t, 50.5, c.Values["value_5"])
	})

	t.Run("handles multiple chunks", func(t *testing.T) {
		callCount := 0
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			callCount++
			// Return different data for each call
			response := `[[1600000000, "9900.0", "10100.0", "10000.5", "10050.2", "50.5"]]`
			_, _ = w.Write([]byte(response))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		// Set time range that requires multiple chunks (300 records per chunk)
		start := time.Unix(1600000000, 0)
		end := start.Add(400 * 60 * time.Second) // 400 minutes = 2 chunks

		records, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.GreaterOrEqual(t, callCount, 2, "should make multiple API calls")
		assert.Greater(t, len(records), 0)
	})

	t.Run("handles API error status", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusBadRequest)
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		_, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "API error")
	})

	t.Run("handles malformed JSON response", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = w.Write([]byte(`invalid json`))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		_, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "decode failed")
	})

	t.Run("handles empty response array", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_, _ = w.Write([]byte(`[]`))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		records, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.Len(t, records, 0)
	})

	t.Run("skips entries with insufficient data", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Only 1 element (timestamp only, no value fields) - below len < 2 threshold
			response := `[[1600000000]]`
			_, _ = w.Write([]byte(response))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		records, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.Len(t, records, 0, "should skip entries with only timestamp")
	})

	t.Run("accepts partial data with fewer fields", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// 3 elements: timestamp + 2 values (fewer than full 6, but valid)
			response := `[[1600000000, "9900.0", "10100.0"]]`
			_, _ = w.Write([]byte(response))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   1,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		records, err := collector.FetchHistorical("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.Len(t, records, 1, "should accept entries with at least 2 elements")
		assert.Equal(t, 9900.0, records[0].Values["value_1"])
		assert.Equal(t, 10100.0, records[0].Values["value_2"])
	})
}

func TestRESTSourceCollector_Source(t *testing.T) {
	collector := NewRESTSourceCollector(config.DataSourceConfig{Name: "test-source"}, zap.NewNop())
	assert.Equal(t, "test-source", collector.Source())
}

func TestNewRESTSourceCollector(t *testing.T) {
	cfg := config.DataSourceConfig{
		Name:        "test-source",
		BaseURL:     "https://api.example.com",
		Granularity: 60,
		MaxRecords:  300,
	}
	logger := zap.NewNop()

	collector := NewRESTSourceCollector(cfg, logger)

	assert.NotNil(t, collector)
	assert.NotNil(t, collector.client)
	assert.Equal(t, 30*time.Second, collector.client.Timeout)
	assert.Equal(t, cfg.BaseURL, collector.cfg.BaseURL)
}

func TestRESTSourceCollector_fetchChunk(t *testing.T) {
	t.Run("parses record data correctly", func(t *testing.T) {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			response := `[
				[1600000000, "9900.0", "10100.0", "10000.5", "10050.2", "50.5"],
				[1600000060, "10050.2", "10200.0", "10000.0", "10150.0", "75.3"]
			]`
			_, _ = w.Write([]byte(response))
		}))
		defer ts.Close()

		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     ts.URL,
			Granularity: 60,
			MaxRecords:  300,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000120, 0)

		records, err := collector.fetchChunk("SAMPLE-1", start, end)

		assert.NoError(t, err)
		assert.Len(t, records, 2)
		assert.Equal(t, 10000.5, records[0].Values["value_3"])
		assert.Equal(t, 10150.0, records[1].Values["value_4"])
	})

	t.Run("handles network error", func(t *testing.T) {
		cfg := config.DataSourceConfig{
			Name:        "test-source",
			BaseURL:     "http://invalid-url-that-does-not-exist.local",
			Granularity: 60,
			MaxRecords:  300,
		}
		collector := NewRESTSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600000060, 0)

		_, err := collector.fetchChunk("SAMPLE-1", start, end)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "request failed")
	})
}
