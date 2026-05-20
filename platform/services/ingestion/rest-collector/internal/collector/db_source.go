// Package collector implements database source collection stub
// Satisfies the Collector interface for database polling sources
package collector

import (
	"fmt"
	"time"

	"go.uber.org/zap"
)

// DBSourceConfig holds database source configuration.
type DBSourceConfig struct {
	Name         string        `mapstructure:"name"`
	Driver       string        `mapstructure:"driver"` // "postgres", "mysql", "clickhouse"
	DSN          string        `mapstructure:"dsn"`
	Query        string        `mapstructure:"query"`
	PollInterval time.Duration `mapstructure:"poll_interval"`
}

// DBSourceCollector implements Collector for database polling.
type DBSourceCollector struct {
	cfg    DBSourceConfig
	logger *zap.Logger
}

// NewDBSourceCollector creates a new database source collector
func NewDBSourceCollector(cfg DBSourceConfig, logger *zap.Logger) *DBSourceCollector {
	return &DBSourceCollector{cfg: cfg, logger: logger}
}

// FetchHistorical fetches data from the configured database
func (c *DBSourceCollector) FetchHistorical(symbol string, start, end time.Time) ([]Record, error) {
	c.logger.Info("Database source collection",
		zap.String("driver", c.cfg.Driver),
		zap.String("symbol", symbol),
		zap.Time("start", start),
		zap.Time("end", end),
	)
	// TODO: Implement database-specific query execution
	// Use database/sql with the configured driver and DSN
	// Execute cfg.Query with symbol, start, end as parameters
	return nil, fmt.Errorf("database source type '%s' not yet fully implemented — configure SOURCE_TYPE=api to use REST", c.cfg.Driver)
}

// Source returns the data source name
func (c *DBSourceCollector) Source() string { return c.cfg.Name }
