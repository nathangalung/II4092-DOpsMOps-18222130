// Package collector implements file source collection stub
// Satisfies the Collector interface for file-based ingestion (local, S3, GCS)
package collector

import (
	"fmt"
	"time"

	"go.uber.org/zap"
)

// FileSourceConfig holds file source configuration.
type FileSourceConfig struct {
	Name   string `mapstructure:"name"`
	Path   string `mapstructure:"path"`   // local path, s3://, gs://
	Format string `mapstructure:"format"` // "csv", "parquet", "json"
	Glob   string `mapstructure:"glob"`   // e.g., "*.csv"
}

// FileSourceCollector implements Collector for file-based ingestion.
type FileSourceCollector struct {
	cfg    FileSourceConfig
	logger *zap.Logger
}

// NewFileSourceCollector creates a new file source collector
func NewFileSourceCollector(cfg FileSourceConfig, logger *zap.Logger) *FileSourceCollector {
	return &FileSourceCollector{cfg: cfg, logger: logger}
}

// FetchHistorical fetches data from the configured file source
func (c *FileSourceCollector) FetchHistorical(symbol string, start, end time.Time) ([]Record, error) {
	c.logger.Info("File source collection",
		zap.String("path", c.cfg.Path),
		zap.String("format", c.cfg.Format),
		zap.String("symbol", symbol),
	)
	// TODO: Implement file reading based on format
	// For local: os.Open + csv/json parser
	// For S3: aws-sdk-go
	// For GCS: cloud.google.com/go/storage
	return nil, fmt.Errorf("file source type '%s' not yet fully implemented — configure SOURCE_TYPE=api to use REST", c.cfg.Format)
}

// Source returns the data source name
func (c *FileSourceCollector) Source() string { return c.cfg.Name }
