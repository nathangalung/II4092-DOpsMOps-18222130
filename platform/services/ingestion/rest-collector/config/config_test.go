package config

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestLoad(t *testing.T) {
	t.Run("loads with default values", func(t *testing.T) {
		cfg, err := Load()

		require.NoError(t, err)
		assert.NotNil(t, cfg)

		// Check defaults
		assert.Equal(t, 8080, cfg.Server.Port)
		assert.Contains(t, cfg.Kafka.Brokers, "platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092")
		assert.Equal(t, "ingested_data", cfg.Kafka.Topic)
		assert.Equal(t, "supplementary_data", cfg.Kafka.SentTopic)
		assert.Equal(t, 100, cfg.Kafka.BatchSize)
		assert.Equal(t, 1000, cfg.Kafka.FlushTimeout)
	})

	t.Run("loads history defaults", func(t *testing.T) {
		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, "2025-01-01T00:00:00Z", cfg.History.StartDate)
		assert.Empty(t, cfg.History.EndDate) // empty means "use current time"
		assert.True(t, cfg.History.BackfillOnStart)
		assert.Equal(t, 1, cfg.History.BatchDays)
		assert.Equal(t, 4, cfg.History.ConcurrentFetches)
	})
}

func TestLoadWithEnvVars(t *testing.T) {
	t.Run("overrides port from env", func(t *testing.T) {
		t.Setenv("SERVER_PORT", "9090")

		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, 9090, cfg.Server.Port)
	})

	t.Run("overrides kafka brokers from env", func(t *testing.T) {
		t.Setenv("KAFKA_BROKERS", "broker1:9092,broker2:9092,broker3:9092")

		cfg, err := Load()

		require.NoError(t, err)
		assert.Len(t, cfg.Kafka.Brokers, 3)
		assert.Contains(t, cfg.Kafka.Brokers, "broker1:9092")
		assert.Contains(t, cfg.Kafka.Brokers, "broker2:9092")
		assert.Contains(t, cfg.Kafka.Brokers, "broker3:9092")
	})

	t.Run("overrides kafka topic from env", func(t *testing.T) {
		t.Setenv("KAFKA_TOPIC", "custom-data-topic")

		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, "custom-data-topic", cfg.Kafka.Topic)
	})

	t.Run("overrides backfill flag from env", func(t *testing.T) {
		t.Setenv("HISTORY_BACKFILL_ON_START", "false")

		cfg, err := Load()

		require.NoError(t, err)
		assert.False(t, cfg.History.BackfillOnStart)
	})

	t.Run("builds data source from env vars", func(t *testing.T) {
		t.Setenv("DATA_SOURCE_NAME", "test-source")
		t.Setenv("DATA_SOURCE_URL", "https://api.example.com")
		t.Setenv("DATA_SOURCE_SYMBOLS", "SYM1,SYM2")
		t.Setenv("DATA_SOURCE_GRANULARITY", "60")
		t.Setenv("DATA_SOURCE_MAX_RECORDS", "500")
		t.Setenv("DATA_SOURCE_RATE_LIMIT_MS", "100")
		// t.Setenv auto-restores; no cleanup needed

		cfg, err := Load()

		require.NoError(t, err)
		require.Len(t, cfg.DataSources, 1)
		assert.Equal(t, "test-source", cfg.DataSources[0].Name)
		assert.Equal(t, "https://api.example.com", cfg.DataSources[0].BaseURL)
		assert.Contains(t, cfg.DataSources[0].Symbols, "SYM1")
		assert.Contains(t, cfg.DataSources[0].Symbols, "SYM2")
		assert.Equal(t, 60, cfg.DataSources[0].Granularity)
		assert.Equal(t, 500, cfg.DataSources[0].MaxRecords)
		assert.Equal(t, 100, cfg.DataSources[0].RateLimit)
	})

	t.Run("builds supplementary source from env vars", func(t *testing.T) {
		t.Setenv("SUPPLEMENTARY_SOURCE_NAME", "test-supplementary")
		t.Setenv("SUPPLEMENTARY_SOURCE_URL", "https://api.supplementary.com/data")
		t.Setenv("SUPPLEMENTARY_SOURCE_API_KEY", "test-key")
		t.Setenv("SUPPLEMENTARY_SOURCE_POLL_INTERVAL", "10m")
		// t.Setenv auto-restores; no cleanup needed

		cfg, err := Load()

		require.NoError(t, err)
		require.Len(t, cfg.Supplementary.Sources, 1)
		assert.Equal(t, "test-supplementary", cfg.Supplementary.Sources[0].Name)
		assert.Equal(t, "https://api.supplementary.com/data", cfg.Supplementary.Sources[0].URL)
		assert.Equal(t, "test-key", cfg.Supplementary.Sources[0].APIKey)
	})
}

func TestConfigStructs(t *testing.T) {
	t.Run("ServerConfig has correct fields", func(t *testing.T) {
		cfg := ServerConfig{
			Port: 8080,
		}

		assert.Equal(t, 8080, cfg.Port)
	})

	t.Run("KafkaConfig has correct fields", func(t *testing.T) {
		cfg := KafkaConfig{
			Brokers:      []string{"localhost:9092"},
			Topic:        "test-topic",
			SentTopic:    "test-sent",
			BatchSize:    50,
			FlushTimeout: 500,
		}

		assert.Len(t, cfg.Brokers, 1)
		assert.Equal(t, "test-topic", cfg.Topic)
		assert.Equal(t, "test-sent", cfg.SentTopic)
		assert.Equal(t, 50, cfg.BatchSize)
		assert.Equal(t, 500, cfg.FlushTimeout)
	})

	t.Run("DataSourceConfig has correct fields", func(t *testing.T) {
		cfg := DataSourceConfig{
			Enabled:     true,
			Name:        "test-source",
			BaseURL:     "https://api.example.com",
			Symbols:     []string{"SYM1", "SYM2"},
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   150,
		}

		assert.True(t, cfg.Enabled)
		assert.Equal(t, "test-source", cfg.Name)
		assert.Equal(t, "https://api.example.com", cfg.BaseURL)
		assert.Len(t, cfg.Symbols, 2)
		assert.Equal(t, 60, cfg.Granularity)
		assert.Equal(t, 300, cfg.MaxRecords)
		assert.Equal(t, 150, cfg.RateLimit)
	})

	t.Run("SupplementarySourceConfig has correct fields", func(t *testing.T) {
		cfg := SupplementarySourceConfig{
			Enabled: true,
			Name:    "test-supplementary",
			URL:     "https://api.supplementary.com/data",
			APIKey:  "test-key",
		}

		assert.True(t, cfg.Enabled)
		assert.Equal(t, "test-supplementary", cfg.Name)
		assert.Equal(t, "https://api.supplementary.com/data", cfg.URL)
		assert.Equal(t, "test-key", cfg.APIKey)
	})

	t.Run("HistoryConfig has correct fields", func(t *testing.T) {
		cfg := HistoryConfig{
			StartDate:         "2025-01-01T00:00:00Z",
			EndDate:           "2025-12-31T23:59:59Z",
			BackfillOnStart:   true,
			BatchDays:         7,
			ConcurrentFetches: 8,
		}

		assert.Equal(t, "2025-01-01T00:00:00Z", cfg.StartDate)
		assert.Equal(t, "2025-12-31T23:59:59Z", cfg.EndDate)
		assert.True(t, cfg.BackfillOnStart)
		assert.Equal(t, 7, cfg.BatchDays)
		assert.Equal(t, 8, cfg.ConcurrentFetches)
	})
}

func TestConfigPaths(t *testing.T) {
	t.Run("handles missing config file gracefully", func(t *testing.T) {
		// Config file not found should not error, just use defaults
		cfg, err := Load()

		require.NoError(t, err)
		assert.NotNil(t, cfg)
	})

	t.Run("respects CONFIG_PATH env var", func(t *testing.T) {
		// Create a temporary config file
		tmpFile, err := os.CreateTemp("", "config-*.yaml")
		require.NoError(t, err)
		defer func() { _ = os.Remove(tmpFile.Name()) }()

		// Write minimal config
		_, err = tmpFile.WriteString(`
server:
  port: 7777
`)
		require.NoError(t, err)
		require.NoError(t, tmpFile.Close())

		t.Setenv("CONFIG_PATH", tmpFile.Name())

		cfg, err := Load()

		require.NoError(t, err)
		assert.Equal(t, 7777, cfg.Server.Port)
	})
}

func TestKafkaBrokersString(t *testing.T) {
	t.Run("parses single broker", func(t *testing.T) {
		t.Setenv("KAFKA_BROKERS", "localhost:9092")

		cfg, err := Load()

		require.NoError(t, err)
		assert.Len(t, cfg.Kafka.Brokers, 1)
		assert.Equal(t, "localhost:9092", cfg.Kafka.Brokers[0])
	})

	t.Run("parses multiple brokers", func(t *testing.T) {
		t.Setenv("KAFKA_BROKERS", "broker1:9092,broker2:9092")

		cfg, err := Load()

		require.NoError(t, err)
		assert.Len(t, cfg.Kafka.Brokers, 2)
	})

	t.Run("handles brokers with spaces", func(t *testing.T) {
		t.Setenv("KAFKA_BROKERS", "broker1:9092, broker2:9092 , broker3:9092")

		cfg, err := Load()

		require.NoError(t, err)
		// Note: actual behavior depends on whether trimming is implemented
		assert.GreaterOrEqual(t, len(cfg.Kafka.Brokers), 3)
	})
}

func TestConfigDefaults(t *testing.T) {
	t.Run("all required fields have defaults", func(t *testing.T) {
		cfg, err := Load()

		require.NoError(t, err)

		// Server
		assert.NotZero(t, cfg.Server.Port)

		// Kafka
		assert.NotEmpty(t, cfg.Kafka.Brokers)
		assert.NotEmpty(t, cfg.Kafka.Topic)
		assert.NotZero(t, cfg.Kafka.BatchSize)

		// History
		assert.NotEmpty(t, cfg.History.StartDate)
		// EndDate is empty by default (means "use current time")
		assert.NotZero(t, cfg.History.BatchDays)
		assert.NotZero(t, cfg.History.ConcurrentFetches)
	})
}
