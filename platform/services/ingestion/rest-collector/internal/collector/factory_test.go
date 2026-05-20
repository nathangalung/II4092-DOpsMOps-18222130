package collector

import (
	"testing"

	"github.com/mlops-platform/rest-collector/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/zap"
)

func TestNewCollector(t *testing.T) {
	logger := zap.NewNop()

	restCfg := []config.DataSourceConfig{
		{
			Enabled:     true,
			Name:        "test-rest",
			BaseURL:     "https://api.example.com",
			Symbols:     []string{"SYMBOL-A"},
			Granularity: 60,
			MaxRecords:  300,
			RateLimit:   150,
		},
	}
	dbCfg := []DBSourceConfig{
		{
			Name:   "test-db",
			Driver: "postgres",
			DSN:    "postgres://localhost/test",
			Query:  "SELECT * FROM records WHERE symbol=$1",
		},
	}
	fileCfg := []FileSourceConfig{
		{
			Name:   "test-file",
			Path:   "/data/records",
			Format: "csv",
			Glob:   "*.csv",
		},
	}

	t.Run("defaults to api when sourceType is empty", func(t *testing.T) {
		t.Setenv("SOURCE_TYPE", "")

		c, err := NewCollector("", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.NotNil(t, c)
		assert.Equal(t, "test-rest", c.Source())
		assert.IsType(t, &RESTSourceCollector{}, c)
	})

	t.Run("reads SOURCE_TYPE env var when sourceType is empty", func(t *testing.T) {
		t.Setenv("SOURCE_TYPE", "database")

		c, err := NewCollector("", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.NotNil(t, c)
		assert.Equal(t, "test-db", c.Source())
		assert.IsType(t, &DBSourceCollector{}, c)
	})

	t.Run("explicit sourceType overrides env var", func(t *testing.T) {
		t.Setenv("SOURCE_TYPE", "database")

		c, err := NewCollector("file", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.NotNil(t, c)
		assert.Equal(t, "test-file", c.Source())
		assert.IsType(t, &FileSourceCollector{}, c)
	})

	t.Run("creates REST collector for api type", func(t *testing.T) {
		c, err := NewCollector("api", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.IsType(t, &RESTSourceCollector{}, c)
		assert.Equal(t, "test-rest", c.Source())
	})

	t.Run("creates REST collector for rest alias", func(t *testing.T) {
		c, err := NewCollector("rest", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.IsType(t, &RESTSourceCollector{}, c)
	})

	t.Run("creates DB collector for database type", func(t *testing.T) {
		c, err := NewCollector("database", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.IsType(t, &DBSourceCollector{}, c)
		assert.Equal(t, "test-db", c.Source())
	})

	t.Run("creates DB collector for db alias", func(t *testing.T) {
		c, err := NewCollector("db", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.IsType(t, &DBSourceCollector{}, c)
	})

	t.Run("creates file collector for file type", func(t *testing.T) {
		c, err := NewCollector("file", restCfg, dbCfg, fileCfg, logger)

		require.NoError(t, err)
		assert.IsType(t, &FileSourceCollector{}, c)
		assert.Equal(t, "test-file", c.Source())
	})

	t.Run("returns error for unknown source type", func(t *testing.T) {
		_, err := NewCollector("kafka", restCfg, dbCfg, fileCfg, logger)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "unknown source type: kafka")
		assert.Contains(t, err.Error(), "available: api, database, file")
	})

	t.Run("returns error when REST configs are empty", func(t *testing.T) {
		_, err := NewCollector("api", nil, dbCfg, fileCfg, logger)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "no REST data sources configured")
	})

	t.Run("returns error when DB configs are empty", func(t *testing.T) {
		_, err := NewCollector("database", restCfg, nil, fileCfg, logger)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "no database sources configured")
	})

	t.Run("returns error when file configs are empty", func(t *testing.T) {
		_, err := NewCollector("file", restCfg, dbCfg, nil, logger)

		assert.Error(t, err)
		assert.Contains(t, err.Error(), "no file sources configured")
	})
}
