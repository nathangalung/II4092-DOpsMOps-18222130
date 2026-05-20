// Package supplementary implements a generic supplementary HTTP data collector.
// Fetches JSON from a configurable URL and extracts fields based on a
// configurable field mapping (RESPONSE_FIELD_MAPPING). No domain-specific
// parsing logic lives here; use-case overlays provide their own parsers.
package supplementary

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/mlops-platform/rest-collector/config"
	"github.com/mlops-platform/rest-collector/internal/producer"
	"go.uber.org/zap"
)

// HTTPSourceCollector fetches supplementary data from a configurable HTTP source
type HTTPSourceCollector struct {
	cfg      config.SupplementarySourceConfig
	client   *http.Client
	producer *producer.KafkaProducer
	logger   *zap.Logger
}

// NewHTTPSourceCollector creates a new HTTP source collector
func NewHTTPSourceCollector(
	cfg config.SupplementarySourceConfig,
	prod *producer.KafkaProducer,
	logger *zap.Logger,
) *HTTPSourceCollector {
	return &HTTPSourceCollector{
		cfg:      cfg,
		client:   &http.Client{Timeout: 30 * time.Second},
		producer: prod,
		logger:   logger,
	}
}

// Run starts the polling loop. If PollInterval is 0, runs once and returns.
func (c *HTTPSourceCollector) Run(ctx context.Context) {
	if !c.cfg.Enabled {
		c.logger.Info("HTTP source collector disabled",
			zap.String("source", c.cfg.Name))
		return
	}

	// Backfill historical data if enabled (one-shot before regular fetch)
	if c.cfg.BackfillEnabled {
		c.backfillHistorical()
	}

	// Regular one-shot fetch
	c.fetch()
	if c.cfg.PollInterval <= 0 {
		c.logger.Info("One-shot fetch complete",
			zap.String("source", c.cfg.Name))
		return
	}

	ticker := time.NewTicker(c.cfg.PollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			c.logger.Info("HTTP source collector stopped",
				zap.String("source", c.cfg.Name))
			return
		case <-ticker.C:
			c.fetch()
		}
	}
}

func (c *HTTPSourceCollector) fetch() {
	url := c.cfg.URL

	// Build HTTP request with proper auth handling
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		c.logger.Error("Failed to create request",
			zap.String("source", c.cfg.Name), zap.Error(err))
		return
	}

	// API key injection: header-based or query-param based
	if c.cfg.APIKey != "" {
		apiKeyHeader := os.Getenv("SUPPLEMENTARY_SOURCE_API_KEY_HEADER")
		apiKeyParam := os.Getenv("SUPPLEMENTARY_SOURCE_API_KEY_PARAM")
		if apiKeyHeader != "" {
			req.Header.Set(apiKeyHeader, c.cfg.APIKey)
		} else {
			paramName := "auth_token"
			if apiKeyParam != "" {
				paramName = apiKeyParam
			}
			q := req.URL.Query()
			q.Set(paramName, c.cfg.APIKey)
			req.URL.RawQuery = q.Encode()
		}
	}

	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "mlops-platform/rest-collector")

	resp, err := c.client.Do(req)
	if err != nil {
		c.logger.Error("HTTP source request failed",
			zap.String("source", c.cfg.Name), zap.Error(err))
		return
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		c.logger.Error("HTTP source API error",
			zap.String("source", c.cfg.Name),
			zap.Int("status", resp.StatusCode),
			zap.String("body", string(body[:min(len(body), 200)])))
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		c.logger.Error("Failed to read response body",
			zap.String("source", c.cfg.Name), zap.Error(err))
		return
	}

	// Parse response using generic JSON parser
	records := c.parseResponse(body)

	if len(records) > 0 {
		if err := c.producer.SendSupplementary(records); err != nil {
			c.logger.Error("Failed to send supplementary data",
				zap.String("source", c.cfg.Name), zap.Error(err))
		} else {
			c.logger.Info("Fetched supplementary data",
				zap.String("source", c.cfg.Name),
				zap.Int("count", len(records)))
		}
	} else {
		c.logger.Info("No records parsed from response",
			zap.String("source", c.cfg.Name),
			zap.Int("body_bytes", len(body)))
	}
}

// fieldMapping holds the parsed RESPONSE_FIELD_MAPPING configuration.
// The mapping is a comma-separated string of dot-delimited JSON paths.
// Supported named fields: timestamp, value (score), title, symbol, url.
// Example: "data.*.timestamp,data.*.value,data.*.title"
// If fewer than 5 fields are provided, remaining fields get defaults.
type fieldMapping struct {
	TimestampPath string
	ValuePath     string
	TitlePath     string
	SymbolPath    string
	URLPath       string
	DataRoot      string // array root path, e.g. "data" or "results"
}

// parseFieldMapping parses RESPONSE_FIELD_MAPPING into a fieldMapping.
// Format options:
//
//	Simple:  "timestamp,value"
//	Named:   "timestamp=data.timestamp,value=data.value,title=data.name"
//	Rooted:  "root=data,timestamp=timestamp,value=value"
func parseFieldMapping(raw string) fieldMapping {
	fm := fieldMapping{}
	if raw == "" {
		return fm
	}

	parts := strings.Split(raw, ",")
	// Check if named format (contains "=")
	if strings.Contains(raw, "=") {
		for _, part := range parts {
			kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
			if len(kv) != 2 {
				continue
			}
			key, val := strings.TrimSpace(kv[0]), strings.TrimSpace(kv[1])
			switch strings.ToLower(key) {
			case "root":
				fm.DataRoot = val
			case "timestamp":
				fm.TimestampPath = val
			case "value", "score":
				fm.ValuePath = val
			case "title":
				fm.TitlePath = val
			case "symbol":
				fm.SymbolPath = val
			case "url":
				fm.URLPath = val
			}
		}
	} else {
		// Positional format: timestamp,value[,title[,symbol[,url]]]
		for i, part := range parts {
			p := strings.TrimSpace(part)
			switch i {
			case 0:
				fm.TimestampPath = p
			case 1:
				fm.ValuePath = p
			case 2:
				fm.TitlePath = p
			case 3:
				fm.SymbolPath = p
			case 4:
				fm.URLPath = p
			}
		}
	}
	return fm
}

// parseResponse parses the JSON body using the configured field mapping
// and returns SupplementaryRecord entries.
func (c *HTTPSourceCollector) parseResponse(
	body []byte,
) []producer.SupplementaryRecord {
	fm := parseFieldMapping(c.cfg.ResponseFieldMapping)
	return parseJSONResponse(body, fm, c.cfg.Name, c.cfg.URL, c.logger)
}

// parseJSONResponse is the generic JSON response parser. It extracts
// records from JSON using the provided field mapping. If no mapping is
// configured it wraps the entire response as a single raw record.
func parseJSONResponse(
	body []byte,
	fm fieldMapping,
	sourceName string,
	sourceURL string,
	logger *zap.Logger,
) []producer.SupplementaryRecord {
	// If no field mapping is configured, wrap the raw JSON
	if fm.TimestampPath == "" && fm.ValuePath == "" {
		return parseRawResponse(body, sourceName, sourceURL, logger)
	}

	// Parse the JSON into a generic structure
	var raw interface{}
	if err := json.Unmarshal(body, &raw); err != nil {
		logger.Error("JSON parse failed",
			zap.String("source", sourceName), zap.Error(err))
		return nil
	}

	// Navigate to the data root if specified
	items := extractArray(raw, fm.DataRoot)
	if items == nil {
		// Try treating the whole response as a single record
		if m, ok := raw.(map[string]interface{}); ok {
			items = []interface{}{m}
		} else {
			logger.Warn("Could not extract array from response",
				zap.String("source", sourceName),
				zap.String("root", fm.DataRoot))
			return nil
		}
	}

	records := make([]producer.SupplementaryRecord, 0, len(items))
	for _, item := range items {
		obj, ok := item.(map[string]interface{})
		if !ok {
			continue
		}

		ts := extractTimestamp(obj, fm.TimestampPath)
		score := extractFloat(obj, fm.ValuePath)
		title := extractString(obj, fm.TitlePath)
		symbol := extractString(obj, fm.SymbolPath)
		urlVal := extractString(obj, fm.URLPath)

		if title == "" {
			title = fmt.Sprintf("%s_record", sourceName)
		}
		if symbol == "" {
			symbol = sourceName
		}
		if urlVal == "" {
			urlVal = sourceURL
		}

		records = append(records, producer.SupplementaryRecord{
			Source:    sourceName,
			Timestamp: ts,
			Title:     title,
			Score:     score,
			Symbol:    symbol,
			URL:       urlVal,
		})
	}
	return records
}

// parseRawResponse wraps the entire JSON body as a single raw record.
// Used when no field mapping is configured.
func parseRawResponse(
	body []byte,
	sourceName string,
	sourceURL string,
	logger *zap.Logger,
) []producer.SupplementaryRecord {
	var raw json.RawMessage
	if err := json.Unmarshal(body, &raw); err != nil {
		logger.Error("Generic parse failed: invalid JSON",
			zap.String("source", sourceName), zap.Error(err))
		return nil
	}

	return []producer.SupplementaryRecord{
		{
			Source:    sourceName,
			Timestamp: time.Now().UTC(),
			Title:     fmt.Sprintf("raw_%s_response", sourceName),
			Score:     0,
			Symbol:    "RAW",
			URL:       sourceURL,
		},
	}
}

// extractArray navigates to a dot-path in the JSON and returns the
// resulting array. If path is empty, tries to use the root value
// directly as an array.
func extractArray(
	data interface{}, path string,
) []interface{} {
	target := data
	if path != "" {
		target = navigatePath(data, path)
	}
	if arr, ok := target.([]interface{}); ok {
		return arr
	}
	return nil
}

// navigatePath traverses a dot-delimited path through nested JSON
// maps. Returns nil if any segment is not found.
func navigatePath(data interface{}, path string) interface{} {
	if path == "" {
		return data
	}
	parts := strings.Split(path, ".")
	current := data
	for _, part := range parts {
		m, ok := current.(map[string]interface{})
		if !ok {
			return nil
		}
		current, ok = m[part]
		if !ok {
			return nil
		}
	}
	return current
}

// extractTimestamp extracts a timestamp from a JSON object at the
// given dot-path. Supports Unix seconds (int/string), Unix millis
// (int > 1e12), and RFC3339 strings.
func extractTimestamp(
	obj map[string]interface{}, path string,
) time.Time {
	if path == "" {
		return time.Now().UTC()
	}
	val := navigatePath(obj, path)
	if val == nil {
		return time.Now().UTC()
	}

	switch v := val.(type) {
	case float64:
		if v > 1e12 {
			return time.UnixMilli(int64(v))
		}
		return time.Unix(int64(v), 0)
	case string:
		// Try RFC3339 first
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			return t
		}
		// Try Unix timestamp string
		if ts, err := strconv.ParseInt(v, 10, 64); err == nil {
			if ts > 1e12 {
				return time.UnixMilli(ts)
			}
			return time.Unix(ts, 0)
		}
		// Try common date formats
		for _, layout := range []string{
			"2006-01-02T15:04:05Z",
			"2006-01-02 15:04:05",
			"2006-01-02",
		} {
			if t, err := time.Parse(layout, v); err == nil {
				return t
			}
		}
	}
	return time.Now().UTC()
}

// extractFloat extracts a float64 from a JSON object at the given
// dot-path. Handles float64, int-like float64, and string values.
func extractFloat(
	obj map[string]interface{}, path string,
) float64 {
	if path == "" {
		return 0
	}
	val := navigatePath(obj, path)
	if val == nil {
		return 0
	}

	switch v := val.(type) {
	case float64:
		return v
	case string:
		f, _ := strconv.ParseFloat(v, 64)
		return f
	}
	return 0
}

// extractString extracts a string from a JSON object at the given
// dot-path. Non-string values are converted via fmt.Sprintf.
func extractString(
	obj map[string]interface{}, path string,
) string {
	if path == "" {
		return ""
	}
	val := navigatePath(obj, path)
	if val == nil {
		return ""
	}

	switch v := val.(type) {
	case string:
		return v
	default:
		return fmt.Sprintf("%v", v)
	}
}

// backfillHistorical fetches historical data using the configured
// backfill URL (or the main URL with date parameters). The generic
// approach re-fetches the source URL; domain-specific backfill logic
// should be implemented in use-case overlays.
func (c *HTTPSourceCollector) backfillHistorical() {
	if c.cfg.BackfillStartDate == "" {
		c.logger.Info(
			"No backfill start date configured, skipping",
			zap.String("source", c.cfg.Name))
		return
	}

	_, err := time.Parse(time.RFC3339, c.cfg.BackfillStartDate)
	if err != nil {
		c.logger.Error("Invalid backfill start date",
			zap.String("raw", c.cfg.BackfillStartDate),
			zap.Error(err))
		return
	}

	c.logger.Info("Starting supplementary backfill",
		zap.String("source", c.cfg.Name),
		zap.String("from", c.cfg.BackfillStartDate))

	// Generic backfill: fetch the configured URL. Domain-specific
	// backfill URLs (with date ranges, pagination, etc.) should be
	// set via the overlay's SUPPLEMENTARY_SOURCE_URL or a dedicated
	// backfill URL config.
	body, err := c.httpGet(c.cfg.URL)
	if err != nil {
		c.logger.Error("Backfill request failed",
			zap.String("source", c.cfg.Name), zap.Error(err))
		return
	}

	records := c.parseResponse(body)
	if len(records) > 0 {
		if err := c.producer.SendSupplementary(records); err != nil {
			c.logger.Error("Failed to send backfill data",
				zap.String("source", c.cfg.Name), zap.Error(err))
		} else {
			c.logger.Info("Backfill complete",
				zap.String("source", c.cfg.Name),
				zap.Int("records", len(records)))
		}
	}
}

// FetchHTTPJSON is a generic HTTP JSON fetcher. It performs a GET
// request to the given URL, parses the response as JSON, and returns
// the decoded result. Callers can use this for ad-hoc HTTP+JSON
// fetching outside the polling loop.
func FetchHTTPJSON(url string, headers map[string]string) (
	interface{}, error,
) {
	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "mlops-platform/rest-collector")
	for k, v := range headers {
		req.Header.Set(k, v)
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("request failed: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf(
			"HTTP %d: %s",
			resp.StatusCode,
			string(body[:min(len(body), 200)]))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read body: %w", err)
	}

	var result interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("JSON decode failed: %w", err)
	}
	return result, nil
}

// httpGet performs a simple GET request and returns the response body
func (c *HTTPSourceCollector) httpGet(url string) ([]byte, error) {
	resp, err := c.client.Get(url)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf(
			"HTTP %d: %s",
			resp.StatusCode,
			string(body[:min(len(body), 200)]))
	}

	return io.ReadAll(resp.Body)
}
