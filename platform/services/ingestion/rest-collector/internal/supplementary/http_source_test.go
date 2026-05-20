package supplementary

import (
	"testing"
	"time"

	"github.com/mlops-platform/rest-collector/config"
	"github.com/stretchr/testify/assert"
	"go.uber.org/zap"
)

func TestNewHTTPSourceCollector(t *testing.T) {
	cfg := config.SupplementarySourceConfig{
		Enabled:      true,
		Name:         "test-source",
		URL:          "https://api.example.com/data",
		APIKey:       "test-key",
		PollInterval: 5 * time.Minute,
	}
	logger := zap.NewNop()

	collector := NewHTTPSourceCollector(cfg, nil, logger)

	assert.NotNil(t, collector)
	assert.NotNil(t, collector.client)
	assert.Equal(t, 30*time.Second, collector.client.Timeout)
	assert.Equal(t, cfg.APIKey, collector.cfg.APIKey)
	assert.Equal(t, cfg.PollInterval, collector.cfg.PollInterval)
}

func TestHTTPSourceCollector_ConfigValidation(t *testing.T) {
	t.Run("collector respects enabled flag", func(t *testing.T) {
		cfg := config.SupplementarySourceConfig{
			Enabled: false,
			Name:    "test-source",
		}
		collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())
		assert.False(t, collector.cfg.Enabled)
	})

	t.Run("collector stores API key", func(t *testing.T) {
		cfg := config.SupplementarySourceConfig{
			Enabled: true,
			Name:    "test-source",
			APIKey:  "my-secret-key",
		}
		collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())
		assert.Equal(t, "my-secret-key", collector.cfg.APIKey)
	})

	t.Run("collector stores source name", func(t *testing.T) {
		cfg := config.SupplementarySourceConfig{
			Enabled: true,
			Name:    "custom-source",
		}
		collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())
		assert.Equal(t, "custom-source", collector.cfg.Name)
	})
}

func TestHTTPSourceCollector_PollIntervalConfig(t *testing.T) {
	testCases := []struct {
		name     string
		interval time.Duration
	}{
		{"1 minute", 1 * time.Minute},
		{"5 minutes", 5 * time.Minute},
		{"1 hour", 1 * time.Hour},
		{"24 hours", 24 * time.Hour},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			cfg := config.SupplementarySourceConfig{
				Name:         "test-source",
				PollInterval: tc.interval,
			}
			collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())
			assert.Equal(t, tc.interval, collector.cfg.PollInterval)
		})
	}
}

func TestHTTPSourceCollector_HTTPClientSetup(t *testing.T) {
	cfg := config.SupplementarySourceConfig{
		Enabled: true,
		Name:    "test-source",
	}
	collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())

	// Verify HTTP client is properly configured
	assert.NotNil(t, collector.client)
	assert.Equal(t, 30*time.Second, collector.client.Timeout)
}

func TestHTTPSourceCollector_URLConstruction(t *testing.T) {
	cfg := config.SupplementarySourceConfig{
		Name:   "test-source",
		URL:    "https://api.example.com/data",
		APIKey: "test-api-key",
	}
	collector := NewHTTPSourceCollector(cfg, nil, zap.NewNop())

	// Test that the URL and API key are properly stored for URL construction
	assert.Equal(t, "https://api.example.com/data", collector.cfg.URL)
	assert.Equal(t, "test-api-key", collector.cfg.APIKey)
}
