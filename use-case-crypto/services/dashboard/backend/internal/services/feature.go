// Feature service for feature store queries.
// Discovers available features dynamically from ClickHouse table columns.
package services

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/mlops-platform/dashboard/internal/config"
)

// Feature represents a feature record.
type Feature struct {
	Timestamp time.Time              `json:"timestamp"`
	Symbol    string                 `json:"symbol"`
	Name      string                 `json:"name"`
	Value     float64                `json:"value"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// FeatureDefinition describes a feature.
type FeatureDefinition struct {
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Type        string   `json:"type"`
	Tags        []string `json:"tags"`
}

// FeatureService handles feature queries.
type FeatureService struct {
	db             *sql.DB
	tableName      string
	excludeColumns map[string]bool
}

// NewFeatureService creates feature service.
func NewFeatureService(cfg *config.Config) *FeatureService {
	dsn := fmt.Sprintf("clickhouse://%s:%d/%s",
		cfg.ClickHouse.Host, cfg.ClickHouse.Port, cfg.ClickHouse.Database)

	tableName := os.Getenv("FEATURES_TABLE")
	if tableName == "" {
		tableName = "features"
	}

	// Columns to exclude from feature list (metadata, not model features).
	// Configurable via FEATURE_EXCLUDE_COLUMNS env var (comma-separated).
	excludeStr := os.Getenv("FEATURE_EXCLUDE_COLUMNS")
	if excludeStr == "" {
		excludeStr = "symbol,timestamp,date,hour,data_type,created_at,computed_at"
	}
	excludeColumns := make(map[string]bool)
	for _, col := range strings.Split(excludeStr, ",") {
		col = strings.TrimSpace(col)
		if col != "" {
			excludeColumns[col] = true
		}
	}

	db, err := sql.Open("clickhouse", dsn)
	if err != nil {
		return &FeatureService{tableName: tableName, excludeColumns: excludeColumns}
	}

	if err := db.Ping(); err != nil {
		db.Close()
		return &FeatureService{tableName: tableName, excludeColumns: excludeColumns}
	}

	return &FeatureService{db: db, tableName: tableName, excludeColumns: excludeColumns}
}

// List returns available features by introspecting the ClickHouse table columns.
// Falls back to FEATURE_DEFINITIONS env var if DB is unavailable.
func (s *FeatureService) List(ctx context.Context, symbol string) ([]FeatureDefinition, error) {
	// Try dynamic discovery from ClickHouse table schema
	if s.db != nil {
		features, err := s.discoverFromTable(ctx)
		if err == nil && len(features) > 0 {
			return features, nil
		}
	}

	// Fallback: read feature definitions from env var
	// Format: "name1:description1:type1,name2:description2:type2"
	if envDefs := os.Getenv("FEATURE_DEFINITIONS"); envDefs != "" {
		return parseFeatureDefinitions(envDefs), nil
	}

	// Last resort: empty list (use-case should configure FEATURE_DEFINITIONS)
	return []FeatureDefinition{}, nil
}

// discoverFromTable introspects ClickHouse table columns to discover features.
func (s *FeatureService) discoverFromTable(ctx context.Context) ([]FeatureDefinition, error) {
	query := fmt.Sprintf(`
		SELECT name, type
		FROM system.columns
		WHERE table = '%s'
		  AND database = currentDatabase()
		ORDER BY position
	`, s.tableName)

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var features []FeatureDefinition
	for rows.Next() {
		var colName, colType string
		if err := rows.Scan(&colName, &colType); err != nil {
			continue
		}

		// Skip metadata columns
		if s.excludeColumns[colName] {
			continue
		}

		// Only include numeric columns as features
		if !isNumericType(colType) {
			continue
		}

		features = append(features, FeatureDefinition{
			Name:        colName,
			Description: colName,
			Type:        mapClickHouseType(colType),
			Tags:        []string{"auto-discovered"},
		})
	}

	return features, nil
}

// Get returns feature values.
func (s *FeatureService) Get(ctx context.Context, name, symbol string) ([]Feature, error) {
	if s.db == nil {
		return []Feature{}, nil
	}

	query := fmt.Sprintf(`
		SELECT timestamp, symbol, ? as name, %s as value
		FROM %s
		WHERE symbol = ?
		ORDER BY timestamp DESC
		LIMIT 100
	`, name, s.tableName)

	rows, err := s.db.QueryContext(ctx, query, name, symbol)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var features []Feature
	for rows.Next() {
		var f Feature
		err := rows.Scan(&f.Timestamp, &f.Symbol, &f.Name, &f.Value)
		if err != nil {
			continue
		}
		features = append(features, f)
	}

	return features, nil
}

// parseFeatureDefinitions parses FEATURE_DEFINITIONS env var.
// Format: "name1:description:type,name2:description:type"
func parseFeatureDefinitions(defs string) []FeatureDefinition {
	var features []FeatureDefinition
	for _, def := range strings.Split(defs, ",") {
		parts := strings.SplitN(strings.TrimSpace(def), ":", 3)
		if len(parts) == 0 || parts[0] == "" {
			continue
		}
		fd := FeatureDefinition{
			Name: parts[0],
			Type: "float64",
			Tags: []string{"configured"},
		}
		if len(parts) >= 2 {
			fd.Description = parts[1]
		} else {
			fd.Description = parts[0]
		}
		if len(parts) >= 3 {
			fd.Type = parts[2]
		}
		features = append(features, fd)
	}
	return features
}

// isNumericType checks if a ClickHouse column type is numeric.
func isNumericType(colType string) bool {
	numericTypes := []string{"Float32", "Float64", "Int8", "Int16", "Int32", "Int64",
		"UInt8", "UInt16", "UInt32", "UInt64", "Decimal"}
	lower := strings.ToLower(colType)
	for _, nt := range numericTypes {
		if strings.Contains(lower, strings.ToLower(nt)) {
			return true
		}
	}
	return false
}

// mapClickHouseType maps ClickHouse types to generic type names.
func mapClickHouseType(colType string) string {
	lower := strings.ToLower(colType)
	if strings.Contains(lower, "float") || strings.Contains(lower, "decimal") {
		return "float64"
	}
	if strings.Contains(lower, "int") {
		return "int64"
	}
	return "float64"
}
