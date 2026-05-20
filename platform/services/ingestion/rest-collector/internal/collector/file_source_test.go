package collector

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

func TestFileSourceCollector_ImplementsCollector(t *testing.T) {
	var _ Collector = &FileSourceCollector{}
}

func TestNewFileSourceCollector(t *testing.T) {
	cfg := FileSourceConfig{
		Name:   "test-file",
		Path:   "/data/records",
		Format: "csv",
		Glob:   "*.csv",
	}
	logger := zap.NewNop()

	c := NewFileSourceCollector(cfg, logger)

	assert.NotNil(t, c)
	assert.Equal(t, cfg, c.cfg)
}

func TestFileSourceCollector_Source(t *testing.T) {
	cfg := FileSourceConfig{Name: "my-s3-source"}
	c := NewFileSourceCollector(cfg, zap.NewNop())

	assert.Equal(t, "my-s3-source", c.Source())
}

func TestFileSourceCollector_FetchHistorical(t *testing.T) {
	t.Run("returns stub error for csv format", func(t *testing.T) {
		cfg := FileSourceConfig{
			Name:   "test-file",
			Path:   "/data/records",
			Format: "csv",
			Glob:   "*.csv",
		}
		c := NewFileSourceCollector(cfg, zap.NewNop())

		start := time.Unix(1600000000, 0)
		end := time.Unix(1600100000, 0)

		result, err := c.FetchHistorical("SYMBOL-A", start, end)

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "not yet fully implemented")
		assert.Contains(t, err.Error(), "csv")
		assert.Contains(t, err.Error(), "SOURCE_TYPE=api")
	})

	t.Run("returns stub error for parquet format", func(t *testing.T) {
		cfg := FileSourceConfig{
			Name:   "test-file",
			Path:   "s3://bucket/data",
			Format: "parquet",
		}
		c := NewFileSourceCollector(cfg, zap.NewNop())

		result, err := c.FetchHistorical("SYMBOL-B", time.Now().UTC(), time.Now().UTC())

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "parquet")
	})

	t.Run("returns stub error for json format", func(t *testing.T) {
		cfg := FileSourceConfig{
			Name:   "test-file",
			Path:   "gs://bucket/data",
			Format: "json",
		}
		c := NewFileSourceCollector(cfg, zap.NewNop())

		result, err := c.FetchHistorical("SYMBOL-C", time.Now().UTC(), time.Now().UTC())

		require.Error(t, err)
		assert.Nil(t, result)
		assert.Contains(t, err.Error(), "json")
	})
}
