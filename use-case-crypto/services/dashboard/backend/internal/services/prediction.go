// Crypto-specific prediction service — uses predicted_price and signal columns.
package services

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"time"

	_ "github.com/ClickHouse/clickhouse-go/v2"
	"github.com/mlops-platform/dashboard/internal/config"
)

// Prediction represents a crypto prediction record with trading signal.
type Prediction struct {
	ID           string    `json:"id"`
	Symbol       string    `json:"symbol"`
	Timestamp    time.Time `json:"timestamp"`
	CurrentPrice float64   `json:"current_price"`
	PredPrice    float64   `json:"predicted_price"`
	Signal       string    `json:"signal"`
	Confidence   float64   `json:"confidence"`
	ModelVersion string    `json:"model_version"`
}

// PredictionService handles prediction queries.
type PredictionService struct {
	db        *sql.DB
	tableName string
}

// NewPredictionService creates prediction service.
func NewPredictionService(cfg *config.Config) *PredictionService {
	dsn := fmt.Sprintf("clickhouse://%s:%d/%s",
		cfg.ClickHouse.Host, cfg.ClickHouse.Port, cfg.ClickHouse.Database)

	tableName := os.Getenv("PREDICTIONS_TABLE")
	if tableName == "" {
		tableName = "crypto_predictions"
	}

	db, err := sql.Open("clickhouse", dsn)
	if err != nil {
		return &PredictionService{tableName: tableName}
	}

	if err := db.Ping(); err != nil {
		db.Close()
		return &PredictionService{tableName: tableName}
	}

	return &PredictionService{db: db, tableName: tableName}
}

// List returns paginated predictions.
func (s *PredictionService) List(ctx context.Context, limit, offset int) ([]Prediction, error) {
	if s.db == nil {
		return []Prediction{}, nil
	}

	query := fmt.Sprintf(`
		SELECT id, symbol, timestamp, current_price, predicted_price, signal, confidence, model_version
		FROM %s
		ORDER BY timestamp DESC
		LIMIT ? OFFSET ?
	`, s.tableName)

	rows, err := s.db.QueryContext(ctx, query, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanPredictions(rows)
}

// Latest returns latest predictions per symbol.
func (s *PredictionService) Latest(ctx context.Context) ([]Prediction, error) {
	if s.db == nil {
		return []Prediction{}, nil
	}

	query := fmt.Sprintf(`
		SELECT id, symbol, timestamp, current_price, predicted_price, signal, confidence, model_version
		FROM %s
		WHERE (symbol, timestamp) IN (
			SELECT symbol, max(timestamp)
			FROM %s
			GROUP BY symbol
		)
	`, s.tableName, s.tableName)

	rows, err := s.db.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanPredictions(rows)
}

// BySymbol returns predictions for specific symbol.
func (s *PredictionService) BySymbol(ctx context.Context, symbol string, limit int) ([]Prediction, error) {
	if s.db == nil {
		return []Prediction{}, nil
	}

	query := fmt.Sprintf(`
		SELECT id, symbol, timestamp, current_price, predicted_price, signal, confidence, model_version
		FROM %s
		WHERE symbol = ?
		ORDER BY timestamp DESC
		LIMIT ?
	`, s.tableName)

	rows, err := s.db.QueryContext(ctx, query, symbol, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	return scanPredictions(rows)
}

// scanPredictions scans rows into predictions.
func scanPredictions(rows *sql.Rows) ([]Prediction, error) {
	if rows == nil {
		return nil, fmt.Errorf("rows is nil")
	}
	var predictions []Prediction
	for rows.Next() {
		var p Prediction
		if err := rows.Scan(&p.ID, &p.Symbol, &p.Timestamp, &p.CurrentPrice, &p.PredPrice, &p.Signal, &p.Confidence, &p.ModelVersion); err != nil {
			return predictions, fmt.Errorf("scan prediction row: %w", err)
		}
		predictions = append(predictions, p)
	}
	if err := rows.Err(); err != nil {
		return predictions, fmt.Errorf("iterate prediction rows: %w", err)
	}
	return predictions, nil
}
