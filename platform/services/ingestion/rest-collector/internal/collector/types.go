// Package collector defines types and interfaces for data collection
package collector

import (
	"encoding/json"
	"time"
)

// Record represents a generic data point from any source.
// Symbol and Timestamp are required identifiers; all numeric values are
// stored in the Values map, keyed by configurable field names.
// This allows any use-case to define its own schema (sensor readings, metrics, etc.).
//
// JSON wire format is FLAT — Values are promoted to top-level fields:
//
//	{"symbol":"X","timestamp":"...","source":"s","value":100,"volume":50}
//
// This allows downstream services (validator, feature engine) to read fields
// directly without nested "values" indirection.
type Record struct {
	Symbol    string             `json:"-"`
	Timestamp time.Time          `json:"-"`
	Source    string             `json:"-"`
	Values    map[string]float64 `json:"-"`
}

// MarshalJSON flattens Values into top-level JSON fields.
func (r Record) MarshalJSON() ([]byte, error) {
	m := make(map[string]any, 3+len(r.Values))
	m["symbol"] = r.Symbol
	m["timestamp"] = r.Timestamp
	m["source"] = r.Source
	for k, v := range r.Values {
		m[k] = v
	}
	return json.Marshal(m)
}

// UnmarshalJSON reads flat JSON into Record, capturing unknown numeric fields as Values.
func (r *Record) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	if v, ok := raw["symbol"]; ok {
		if err := json.Unmarshal(v, &r.Symbol); err != nil {
			return err
		}
		delete(raw, "symbol")
	}
	if v, ok := raw["timestamp"]; ok {
		if err := json.Unmarshal(v, &r.Timestamp); err != nil {
			return err
		}
		delete(raw, "timestamp")
	}
	if v, ok := raw["source"]; ok {
		if err := json.Unmarshal(v, &r.Source); err != nil {
			return err
		}
		delete(raw, "source")
	}

	r.Values = make(map[string]float64, len(raw))
	for k, v := range raw {
		var f float64
		if err := json.Unmarshal(v, &f); err == nil {
			r.Values[k] = f
		}
	}

	return nil
}

// Collector interface for data source collection
type Collector interface {
	// FetchHistorical fetches historical data for a symbol within time range
	FetchHistorical(symbol string, start, end time.Time) ([]Record, error)
	// Source returns the data source name
	Source() string
}
