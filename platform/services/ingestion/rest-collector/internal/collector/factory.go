// Package collector provides a factory for creating Collector instances
// based on the configured source type (api, database, file)
package collector

import (
	"fmt"
	"os"

	"github.com/mlops-platform/rest-collector/config"
	"go.uber.org/zap"
)

// NewCollector creates a Collector based on the source type.
// Reads SOURCE_TYPE env var if sourceType is empty. Defaults to "api".
func NewCollector(sourceType string, restCfg []config.DataSourceConfig, dbCfg []DBSourceConfig, fileCfg []FileSourceConfig, logger *zap.Logger) (Collector, error) {
	if sourceType == "" {
		sourceType = os.Getenv("SOURCE_TYPE")
	}
	if sourceType == "" {
		sourceType = "api"
	}

	switch sourceType {
	case "api", "rest":
		if len(restCfg) == 0 {
			return nil, fmt.Errorf("no REST data sources configured")
		}
		return NewRESTSourceCollector(restCfg[0], logger), nil
	case "database", "db":
		if len(dbCfg) == 0 {
			return nil, fmt.Errorf("no database sources configured")
		}
		return NewDBSourceCollector(dbCfg[0], logger), nil
	case "file":
		if len(fileCfg) == 0 {
			return nil, fmt.Errorf("no file sources configured")
		}
		return NewFileSourceCollector(fileCfg[0], logger), nil
	default:
		return nil, fmt.Errorf("unknown source type: %s (available: api, database, file)", sourceType)
	}
}
