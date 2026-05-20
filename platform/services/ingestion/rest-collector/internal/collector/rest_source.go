// Package collector implements a generic REST API data source client.
// Supports two independent polling paths:
//   - FetchHistorical/fetchChunk: array-of-arrays historical series
//     (configurable field mapping via RESPONSE_FIELD_MAPPING).
//   - FetchEndpoint: declarative single-endpoint polling driven by
//     config.EndpointConfig — covers object responses (e.g. snapshot
//     quotes), array-of-objects with cursor pagination (e.g. incremental
//     event streams), and arbitrary field/timestamp/transform mappings.
//
// No domain-specific field names, paths, or transforms live in this file.
// All API-shape knowledge is expressed in configuration (values.yaml or
// a Kubernetes ConfigMap mounted into the container).
package collector

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mlops-platform/rest-collector/config"
	"go.uber.org/zap"
)

// Default field mapping for array-style API responses.
// Override with RESPONSE_FIELD_MAPPING env var (comma-separated).
// Example: "timestamp,value_1,value_2,value_3,value_4,value_5"
var defaultFieldMapping = []string{
	"timestamp", "value_1", "value_2",
	"value_3", "value_4", "value_5",
}

func getFieldMapping() []string {
	if mapping := os.Getenv("RESPONSE_FIELD_MAPPING"); mapping != "" {
		return strings.Split(mapping, ",")
	}
	return defaultFieldMapping
}

// RESTSourceCollector fetches data from a configurable REST API
type RESTSourceCollector struct {
	cfg          config.DataSourceConfig
	client       *http.Client
	logger       *zap.Logger
	fieldMapping []string
}

// NewRESTSourceCollector creates a new REST data source collector
func NewRESTSourceCollector(cfg config.DataSourceConfig, logger *zap.Logger) *RESTSourceCollector {
	return &RESTSourceCollector{
		cfg: cfg,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger:       logger,
		fieldMapping: getFieldMapping(),
	}
}

// FetchHistorical fetches data from the configured REST API
// Automatically chunks requests based on MaxRecords configuration
func (c *RESTSourceCollector) FetchHistorical(symbol string, start, end time.Time) ([]Record, error) {
	var allRecords []Record

	maxRecords := c.cfg.MaxRecords
	if maxRecords <= 0 {
		maxRecords = 300
	}
	granularity := time.Duration(c.cfg.Granularity) * time.Second
	chunkDuration := time.Duration(maxRecords) * granularity

	rateLimit := c.cfg.RateLimit
	if rateLimit <= 0 {
		rateLimit = 150
	}

	current := start
	for current.Before(end) {
		chunkEnd := current.Add(chunkDuration)
		if chunkEnd.After(end) {
			chunkEnd = end
		}

		records, err := c.fetchChunkWithRetry(symbol, current, chunkEnd, 3)
		if err != nil {
			c.logger.Error("Failed to fetch chunk after retries",
				zap.String("source", c.cfg.Name),
				zap.String("symbol", symbol),
				zap.Time("start", current),
				zap.Error(err))
			return allRecords, err
		}

		allRecords = append(allRecords, records...)
		current = chunkEnd

		// Rate limiting based on configured rate
		time.Sleep(time.Duration(rateLimit) * time.Millisecond)
	}

	c.logger.Info("Fetched historical data",
		zap.String("source", c.cfg.Name),
		zap.String("symbol", symbol),
		zap.Int("records", len(allRecords)))

	return allRecords, nil
}

// fetchChunkWithRetry retries fetchChunk with exponential backoff
func (c *RESTSourceCollector) fetchChunkWithRetry(symbol string, start, end time.Time, maxRetries int) ([]Record, error) {
	var lastErr error
	for attempt := 0; attempt <= maxRetries; attempt++ {
		if attempt > 0 {
			delay := time.Duration(attempt) * 2 * time.Second
			c.logger.Info("Retrying chunk fetch",
				zap.String("source", c.cfg.Name),
				zap.String("symbol", symbol),
				zap.Int("attempt", attempt),
				zap.Duration("delay", delay))
			time.Sleep(delay)
		}
		records, err := c.fetchChunk(symbol, start, end)
		if err == nil {
			return records, nil
		}
		lastErr = err
		c.logger.Warn("Chunk fetch attempt failed",
			zap.String("source", c.cfg.Name),
			zap.String("symbol", symbol),
			zap.Int("attempt", attempt),
			zap.Error(err))
	}
	return nil, lastErr
}

func (c *RESTSourceCollector) fetchChunk(symbol string, start, end time.Time) ([]Record, error) {
	var u string
	if strings.Contains(c.cfg.BaseURL, "{symbol}") {
		// Template mode: substitute placeholders in URL
		u = strings.ReplaceAll(c.cfg.BaseURL, "{symbol}", symbol)
		u = strings.ReplaceAll(u, "{granularity}", strconv.Itoa(c.cfg.Granularity))
		u = strings.ReplaceAll(u, "{start}", start.Format(time.RFC3339))
		u = strings.ReplaceAll(u, "{end}", end.Format(time.RFC3339))
	} else {
		// Default: append as query parameters
		u = fmt.Sprintf("%s?symbol=%s&granularity=%d&start=%s&end=%s",
			c.cfg.BaseURL, symbol, c.cfg.Granularity,
			start.Format(time.RFC3339), end.Format(time.RFC3339))
	}

	resp, err := c.client.Get(u)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API error: status %d", resp.StatusCode)
	}

	// Generic response parsing: expects array of arrays
	// Field mapping is configurable via RESPONSE_FIELD_MAPPING env var.
	// First element is always treated as Unix timestamp.
	var raw [][]json.Number
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("decode failed: %w", err)
	}

	records := make([]Record, 0, len(raw))
	for _, r := range raw {
		if len(r) < 2 {
			continue
		}

		ts, _ := r[0].Int64()
		values := make(map[string]float64)

		// Map remaining array elements to field names using configured mapping
		for i := 1; i < len(r) && i < len(c.fieldMapping); i++ {
			fieldName := strings.TrimSpace(c.fieldMapping[i])
			if fieldName == "timestamp" || fieldName == "" {
				continue
			}
			val, err := strconv.ParseFloat(r[i].String(), 64)
			if err == nil {
				values[fieldName] = val
			}
		}

		records = append(records, Record{
			Symbol:    symbol,
			Timestamp: time.Unix(ts, 0),
			Source:    c.cfg.Name,
			Values:    values,
		})
	}

	return records, nil
}

// FetchSince fetches all records for a symbol produced since the given
// timestamp up to "now". It is the incremental counterpart to FetchHistorical
// and is used by the continuous-polling loop, which persists the newest
// observed timestamp between ticks. A zero `since` bootstraps a 5-minute
// look-back window.
func (c *RESTSourceCollector) FetchSince(symbol string, since time.Time) ([]Record, error) {
	now := time.Now().UTC()
	if since.IsZero() {
		since = now.Add(-5 * time.Minute)
	}
	return c.FetchHistorical(symbol, since, now)
}

// Source returns the data source name
func (c *RESTSourceCollector) Source() string {
	return c.cfg.Name
}

// ---------------------------------------------------------------------------
// Generic endpoint polling
// ---------------------------------------------------------------------------
//
// The three response kinds below cover every HTTP-JSON REST API we've
// encountered for market-data / telemetry-style feeds:
//
//   "object"            — { "price": "...", "bid": "...", "time": "..." }
//   "array_of_objects"  — [ { "id": 1, "price": "...", "time": "..." }, ... ]
//   "array_of_arrays"   — [ [ts, v1, v2, ...], ... ]  (use FetchHistorical)
//
// For array_of_objects we support cursor pagination where the upstream
// API returns only records after an opaque cursor (e.g. numeric id).
// The collector tracks the cursor in EndpointState across calls and
// sends it back as a query parameter on the next request.

// EndpointState carries cursor/timestamp state between polling calls for
// a single (endpoint, symbol) tuple. Opaque to callers — just persist it.
type EndpointState struct {
	// Cursor is the string form of the last-seen cursor value. For a
	// numeric id cursor (CursorConfig.Type == "after_id") this is the
	// decimal representation of the highest observed integer. Empty
	// means "no cursor yet".
	Cursor string
	// LastTime is the newest record timestamp we've produced, used for
	// idempotent "after_timestamp" cursors.
	LastTime time.Time
}

// FetchEndpoint polls a single configured endpoint for a symbol and
// returns produced records plus the new EndpointState. The state is
// returned even on partial failure so the caller doesn't re-process the
// same cursor on retry.
func (c *RESTSourceCollector) FetchEndpoint(
	ep config.EndpointConfig,
	symbol string,
	state EndpointState,
) ([]Record, EndpointState, error) {
	reqURL, err := c.buildEndpointURL(ep, symbol, state)
	if err != nil {
		return nil, state, fmt.Errorf("endpoint %s url build failed: %w", ep.Name, err)
	}

	method := strings.ToUpper(strings.TrimSpace(ep.Method))
	if method == "" {
		method = http.MethodGet
	}

	req, err := http.NewRequest(method, reqURL, nil)
	if err != nil {
		return nil, state, fmt.Errorf("endpoint %s request build failed: %w", ep.Name, err)
	}
	for k, v := range ep.Headers {
		req.Header.Set(k, v)
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, state, fmt.Errorf("endpoint %s request failed: %w", ep.Name, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return nil, state, fmt.Errorf("endpoint %s status %d", ep.Name, resp.StatusCode)
	}

	var raw json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, state, fmt.Errorf("endpoint %s decode failed: %w", ep.Name, err)
	}

	recordSource := c.cfg.Name
	if ep.SourceSuffix != "" {
		recordSource = c.cfg.Name + ep.SourceSuffix
	}

	switch strings.ToLower(ep.Response.Kind) {
	case "object", "":
		return c.parseObjectResponse(ep, symbol, recordSource, state, raw)
	case "array_of_objects":
		return c.parseArrayOfObjectsResponse(ep, symbol, recordSource, state, raw)
	case "array_of_arrays":
		return c.parseArrayOfArraysResponse(ep, symbol, recordSource, state, raw)
	default:
		return nil, state, fmt.Errorf("endpoint %s: unsupported response.kind %q", ep.Name, ep.Response.Kind)
	}
}

// buildEndpointURL composes the request URL from APIBaseURL + ep.Path,
// performing {symbol} substitution and appending the cursor query param
// if one is configured and non-empty.
func (c *RESTSourceCollector) buildEndpointURL(
	ep config.EndpointConfig,
	symbol string,
	state EndpointState,
) (string, error) {
	path := strings.ReplaceAll(ep.Path, "{symbol}", symbol)

	var composed string
	if strings.HasPrefix(path, "http://") || strings.HasPrefix(path, "https://") {
		composed = path
	} else {
		base := strings.TrimRight(c.cfg.APIBaseURL, "/")
		if base == "" {
			return "", fmt.Errorf("APIBaseURL is required for relative endpoint paths")
		}
		if !strings.HasPrefix(path, "/") {
			path = "/" + path
		}
		composed = base + path
	}

	parsed, err := url.Parse(composed)
	if err != nil {
		return "", err
	}
	q := parsed.Query()
	for k, v := range ep.QueryParams {
		q.Set(k, strings.ReplaceAll(v, "{symbol}", symbol))
	}
	cursorValue := endpointCursorValue(ep, state)
	if ep.Cursor.QueryParam != "" && cursorValue != "" {
		q.Set(ep.Cursor.QueryParam, cursorValue)
	}
	parsed.RawQuery = q.Encode()
	return parsed.String(), nil
}

// endpointCursorValue returns the string to send back to the API for
// the configured cursor type, or "" if no cursor has been established.
func endpointCursorValue(ep config.EndpointConfig, state EndpointState) string {
	switch strings.ToLower(ep.Cursor.Type) {
	case "after_id":
		return state.Cursor
	case "after_timestamp":
		if state.LastTime.IsZero() {
			return ""
		}
		return state.LastTime.UTC().Format(time.RFC3339Nano)
	default:
		return ""
	}
}

// parseObjectResponse handles a single-object response (e.g. quote snapshot).
func (c *RESTSourceCollector) parseObjectResponse(
	ep config.EndpointConfig,
	symbol, source string,
	state EndpointState,
	raw json.RawMessage,
) ([]Record, EndpointState, error) {
	var obj map[string]json.RawMessage
	if err := json.Unmarshal(raw, &obj); err != nil {
		return nil, state, fmt.Errorf("endpoint %s: object decode: %w", ep.Name, err)
	}
	rec, newState, ok := c.objectToRecord(ep, symbol, source, state, obj)
	if !ok {
		return nil, state, nil
	}
	return []Record{rec}, newState, nil
}

// parseArrayOfObjectsResponse handles [ {...}, {...} ] responses. Records
// whose cursor field value is <= the incoming cursor are filtered out so
// the collector is safe to re-poll without duplicates.
func (c *RESTSourceCollector) parseArrayOfObjectsResponse(
	ep config.EndpointConfig,
	symbol, source string,
	state EndpointState,
	raw json.RawMessage,
) ([]Record, EndpointState, error) {
	var arr []map[string]json.RawMessage
	if err := json.Unmarshal(raw, &arr); err != nil {
		return nil, state, fmt.Errorf("endpoint %s: array decode: %w", ep.Name, err)
	}

	records := make([]Record, 0, len(arr))
	newState := state
	for _, obj := range arr {
		rec, updated, ok := c.objectToRecord(ep, symbol, source, newState, obj)
		if !ok {
			continue
		}
		records = append(records, rec)
		newState = updated
	}
	return records, newState, nil
}

// parseArrayOfArraysResponse handles [ [ts, v1, v2, ...], ... ] responses
// using ep.Response.ArrayFields for positional naming.
func (c *RESTSourceCollector) parseArrayOfArraysResponse(
	ep config.EndpointConfig,
	symbol, source string,
	state EndpointState,
	raw json.RawMessage,
) ([]Record, EndpointState, error) {
	var arr [][]json.Number
	if err := json.Unmarshal(raw, &arr); err != nil {
		return nil, state, fmt.Errorf("endpoint %s: array-of-arrays decode: %w", ep.Name, err)
	}
	if len(ep.Response.ArrayFields) == 0 {
		return nil, state, fmt.Errorf("endpoint %s: array_of_arrays requires response.array_fields", ep.Name)
	}

	records := make([]Record, 0, len(arr))
	newState := state
	for _, row := range arr {
		if len(row) < 2 {
			continue
		}
		values := make(map[string]float64, len(row))
		var rowTS time.Time
		for i, num := range row {
			if i >= len(ep.Response.ArrayFields) {
				break
			}
			field := strings.TrimSpace(ep.Response.ArrayFields[i])
			if field == "" {
				continue
			}
			if field == ep.Response.TimestampField || field == "timestamp" {
				if iv, err := num.Int64(); err == nil {
					rowTS = parseTimestampUnit(iv, ep.Response.TimestampUnit)
				}
				continue
			}
			if v, err := strconv.ParseFloat(num.String(), 64); err == nil {
				values[field] = v
			}
		}
		if rowTS.IsZero() {
			rowTS = time.Now().UTC()
		}
		records = append(records, Record{
			Symbol:    symbol,
			Timestamp: rowTS,
			Source:    source,
			Values:    values,
		})
		if rowTS.After(newState.LastTime) {
			newState.LastTime = rowTS
		}
	}
	return records, newState, nil
}

// objectToRecord converts a JSON object into a Record using the endpoint's
// field_mapping, applying value_transforms, parsing the timestamp, and
// updating the returned state with any new cursor.
// Returns ok=false when the object fails the cursor filter (already seen).
func (c *RESTSourceCollector) objectToRecord(
	ep config.EndpointConfig,
	symbol, source string,
	state EndpointState,
	obj map[string]json.RawMessage,
) (Record, EndpointState, bool) {
	newState := state

	if ep.Cursor.Field != "" && strings.EqualFold(ep.Cursor.Type, "after_id") {
		if raw, ok := obj[ep.Cursor.Field]; ok {
			if skip, updated := cursorUpdate(raw, newState); skip {
				return Record{}, state, false
			} else {
				newState = updated
			}
		}
	}

	values := make(map[string]float64, len(ep.Response.FieldMapping))
	for jsonKey, outKey := range ep.Response.FieldMapping {
		rawVal, ok := obj[jsonKey]
		if !ok {
			continue
		}
		if transform, hasTransform := ep.ValueTransforms[jsonKey]; hasTransform {
			if f, ok := applyValueTransform(transform, rawVal); ok {
				values[outKey] = f
			}
			continue
		}
		if f, ok := parseJSONNumber(rawVal); ok {
			values[outKey] = f
		}
	}

	// Cursor field is promoted into Values as a float even when not
	// explicitly listed in field_mapping — so downstream consumers can
	// correlate records with the upstream cursor identifier.
	if ep.Cursor.Field != "" {
		if raw, ok := obj[ep.Cursor.Field]; ok {
			if f, ok := parseJSONNumber(raw); ok {
				values[ep.Cursor.Field] = f
			}
		}
	}

	ts := time.Now().UTC()
	if ep.Response.TimestampField != "" {
		if raw, ok := obj[ep.Response.TimestampField]; ok {
			if parsed, ok := parseTimestamp(raw, ep.Response.TimestampUnit); ok {
				ts = parsed
			}
		}
	}
	if ts.After(newState.LastTime) {
		newState.LastTime = ts
	}

	return Record{
		Symbol:    symbol,
		Timestamp: ts,
		Source:    source,
		Values:    values,
	}, newState, true
}

// cursorUpdate returns (skip, newState) for an integer after_id cursor.
// If the incoming id <= state.Cursor we return skip=true. If the incoming
// id > state.Cursor, newState.Cursor is advanced to the incoming value.
func cursorUpdate(raw json.RawMessage, state EndpointState) (skip bool, newState EndpointState) {
	newState = state
	v, ok := parseJSONNumber(raw)
	if !ok {
		return false, state
	}
	incoming := int64(v)
	if state.Cursor != "" {
		prev, err := strconv.ParseInt(state.Cursor, 10, 64)
		if err == nil && incoming <= prev {
			return true, state
		}
	}
	newState.Cursor = strconv.FormatInt(incoming, 10)
	return false, newState
}

// applyValueTransform converts a non-numeric JSON value into a float64
// according to a named transform. Unknown transforms return ok=false.
//
// Supported transforms:
//   "buy_sell_binary"  — "buy" → +1.0, anything else → -1.0
//   "boolean"          — true → 1.0, false → 0.0
func applyValueTransform(name string, raw json.RawMessage) (float64, bool) {
	switch strings.ToLower(name) {
	case "buy_sell_binary":
		var s string
		if err := json.Unmarshal(raw, &s); err != nil {
			return 0, false
		}
		if strings.EqualFold(strings.TrimSpace(s), "buy") {
			return 1.0, true
		}
		return -1.0, true
	case "boolean":
		var b bool
		if err := json.Unmarshal(raw, &b); err == nil {
			if b {
				return 1.0, true
			}
			return 0.0, true
		}
		return 0, false
	default:
		return 0, false
	}
}

// parseJSONNumber tries to interpret a json.RawMessage as a float64, whether
// it was sent on the wire as a number (3.14) or as a numeric string ("3.14").
func parseJSONNumber(raw json.RawMessage) (float64, bool) {
	var num json.Number
	if err := json.Unmarshal(raw, &num); err == nil {
		if f, err := num.Float64(); err == nil {
			return f, true
		}
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		if f, err := strconv.ParseFloat(strings.TrimSpace(s), 64); err == nil {
			return f, true
		}
	}
	return 0, false
}

// parseTimestamp parses a timestamp field value using the configured unit.
// Accepts both numeric (unix) and RFC3339 strings.
func parseTimestamp(raw json.RawMessage, unit string) (time.Time, bool) {
	unit = strings.ToLower(strings.TrimSpace(unit))
	if unit == "" || unit == "rfc3339" {
		var s string
		if err := json.Unmarshal(raw, &s); err == nil {
			if t, err := time.Parse(time.RFC3339Nano, s); err == nil {
				return t, true
			}
			if t, err := time.Parse(time.RFC3339, s); err == nil {
				return t, true
			}
		}
	}
	var num json.Number
	if err := json.Unmarshal(raw, &num); err == nil {
		if iv, err := num.Int64(); err == nil {
			return parseTimestampUnit(iv, unit), true
		}
	}
	var s string
	if err := json.Unmarshal(raw, &s); err == nil {
		if iv, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64); err == nil {
			return parseTimestampUnit(iv, unit), true
		}
	}
	return time.Time{}, false
}

// parseTimestampUnit converts an integer timestamp to time.Time using
// the configured unit (default "s").
func parseTimestampUnit(v int64, unit string) time.Time {
	switch strings.ToLower(strings.TrimSpace(unit)) {
	case "ms":
		return time.Unix(0, v*int64(time.Millisecond)).UTC()
	case "us":
		return time.Unix(0, v*int64(time.Microsecond)).UTC()
	case "ns":
		return time.Unix(0, v).UTC()
	default: // "s" or empty
		return time.Unix(v, 0).UTC()
	}
}
