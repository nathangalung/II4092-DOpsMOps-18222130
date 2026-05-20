package collector

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

func TestDBSourceCollector_ImplementsCollector(t *testing.T) {
	var _ Collector = &DBSourceCollector{}
}

func TestNewDBSourceCollector(t *testing.T) {
	cfg := DBSourceConfig{
		Name:         "test-db",
		Driver:       "postgres",
		DSN:          "postgres://localhost:5432/testdb",
		Query:        "SELECT * FROM records WHERE symbol=$1 AND ts BETWEEN $2 AND $3",
		PollInterval: 5 * time.Minute,
	}
	logger := zap.NewNop()

	c := NewDBSourceCollector(cfg, logger)

	assert.NotNil(t, c)
	assert.Equal(t, cfg, c.cfg)
}

func TestDBSourceCollector_Source(t *testing.T) {
	cfg := DBSourceConfig{Name: "my-postgres"}
	c := NewDBSourceCollector(cfg, zap.NewNop())

	assert.Equal(t, "my-postgres", c.Source())
}

func TestDBSourceCollector_FetchHistorical(t *testing.T) {
	t.Run("returns stub error for postgres", func(t *testing.T) {
		cfg := DBSourceConfig{
			Name:   "test-db",
			Driver: "postgres",
			DSN:    "postgres://localhost/test",
			Query:  "SELECT * FROM records",
		}
		c := NewDBSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600100000, 0)

		result, err := c.FetchHistorical("SYMBOL-A", start, end)

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "not yet fully implemented")
		assert.Contains(t, err.Error(), "postgres")
		assert.Contains(t, err.Error(), "SOURCE_TYPE=api")
	})

	t.Run("returns stub error for mysql", func(t *testing.T) {
		cfg := DBSourceConfig{
			Name:   "test-db",
			Driver: "mysql",
		}
		c := NewDBSourceCollector(cfg, zap.NewNop())

		result, err := c.FetchHistorical("SYMBOL-B", time.Now().UTC(), time.Now().UTC())

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "mysql")
	})

	t.Run("returns stub error for clickhouse", func(t *testing.T) {
		cfg := DBSourceConfig{
			Name:   "test-db",
			Driver: "clickhouse",
		}
		c := NewDBSourceCollector(cfg, zap.NewNop())

		result, err := c.FetchHistorical("SYMBOL-C", time.Now().UTC(), time.Now().UTC())

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "clickhouse")
	})
}
