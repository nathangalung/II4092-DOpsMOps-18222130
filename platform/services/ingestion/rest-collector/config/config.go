// Package config handles configuration for rest-collector
// Supports configurable REST API data sources for historical data
// Plus supplementary HTTP data sources
package config

import (
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/viper"
)

type Config struct {
	Server        ServerConfig        `mapstructure:"server"`
	Kafka         KafkaConfig         `mapstructure:"kafka"`
	DataSources   []DataSourceConfig  `mapstructure:"data_sources"`
	Supplementary SupplementaryConfig `mapstructure:"supplementary"`
	History       HistoryConfig       `mapstructure:"history"`
	Polling       PollingConfig       `mapstructure:"polling"`
}

// PollingConfig controls the long-running polling loop.
//
// HistoricalRefreshInterval drives the FetchHistorical "latest window"
// poll (domain-agnostic time-series refresh). Per-endpoint polling is
// defined declaratively inside each DataSourceConfig.Endpoints entry —
// the rest-collector spawns one goroutine per (data_source, endpoint,
// symbol) triple using that entry's own PollInterval.
type PollingConfig struct {
	Enabled                   bool          `mapstructure:"enabled"`
	HistoricalRefreshInterval time.Duration `mapstructure:"historical_refresh_interval"`
}

type ServerConfig struct {
	Port int `mapstructure:"port"`
}

type KafkaConfig struct {
	Brokers      []string `mapstructure:"brokers"`
	Topic        string   `mapstructure:"topic"`
	SentTopic    string   `mapstructure:"supplementary_topic"`
	BatchSize    int      `mapstructure:"batch_size"`
	FlushTimeout int      `mapstructure:"flush_timeout_ms"`
	// Security wiring — matches the platform's pipeline-config /
	// crypto-app-consumer envFrom contract (KAFKA_* env keys). Empty
	// SecurityProtocol leaves the producer on PLAINTEXT (platform default).
	SecurityProtocol string `mapstructure:"security_protocol"`
	SASLMechanism    string `mapstructure:"sasl_mechanism"`
	SASLUsername     string `mapstructure:"sasl_username"`
	SASLPassword     string `mapstructure:"sasl_password"`
	SSLCALocation    string `mapstructure:"ssl_ca_location"`
}

type DataSourceConfig struct {
	Enabled     bool             `mapstructure:"enabled"`
	Name        string           `mapstructure:"name"`
	BaseURL     string           `mapstructure:"base_url"`     // template URL for historical (FetchHistorical)
	APIBaseURL  string           `mapstructure:"api_base_url"` // base URL that EndpointConfig.Path is resolved against
	Symbols     []string         `mapstructure:"symbols"`
	Granularity int              `mapstructure:"granularity"` // seconds
	MaxRecords  int              `mapstructure:"max_records"`
	RateLimit   int              `mapstructure:"rate_limit_ms"`
	Endpoints   []EndpointConfig `mapstructure:"endpoints"`
}

// EndpointConfig declares a single REST endpoint poll loop. One loop is
// spawned per (data_source, endpoint, symbol) triple. The endpoint is
// fully self-describing: URL path, HTTP method, poll cadence, response
// shape, cursor pagination, and value transforms.
type EndpointConfig struct {
	Name            string            `mapstructure:"name"`
	Enabled         bool              `mapstructure:"enabled"`
	Path            string            `mapstructure:"path"` // relative to APIBaseURL; supports {symbol}
	Method          string            `mapstructure:"method"`
	Headers         map[string]string `mapstructure:"headers"`
	QueryParams     map[string]string `mapstructure:"query_params"` // constant query params; supports {symbol}
	PollInterval    time.Duration     `mapstructure:"poll_interval"`
	KafkaTopic      string            `mapstructure:"kafka_topic"`   // empty => Kafka.Topic (default)
	SourceSuffix    string            `mapstructure:"source_suffix"` // appended to DataSourceConfig.Name for record.Source
	Response        ResponseConfig    `mapstructure:"response"`
	Cursor          CursorConfig      `mapstructure:"cursor"`
	ValueTransforms map[string]string `mapstructure:"value_transforms"` // json_field -> transform name
}

// ResponseConfig describes how to parse the endpoint's response payload.
//
//   Kind: one of "object" (single JSON object), "array_of_objects"
//         (JSON list of objects), "array_of_arrays" (JSON list of
//         positional arrays like OHLCV candles).
//   FieldMapping:   json_field -> output_key, used for object /
//                   array_of_objects. Only listed fields are copied.
//   ArrayFields:    positional field names for array_of_arrays. Entry
//                   at position i names the i-th element of the row.
//   TimestampField: which output key (ArrayFields) or JSON field
//                   (FieldMapping) holds the record timestamp.
//   TimestampUnit:  "s" (default), "ms", "us", "ns", or "rfc3339".
type ResponseConfig struct {
	Kind           string            `mapstructure:"kind"`
	FieldMapping   map[string]string `mapstructure:"field_mapping"`
	ArrayFields    []string          `mapstructure:"array_fields"`
	TimestampField string            `mapstructure:"timestamp_field"`
	TimestampUnit  string            `mapstructure:"timestamp_unit"`
}

// CursorConfig describes incremental-pagination cursor handling for
// array_of_objects endpoints.
//
//   Type:       "none" (default), "after_id", "after_timestamp".
//   Field:      JSON field name in each response object holding the
//               cursor value (e.g. "trade_id").
//   QueryParam: URL query parameter used to send the last-seen cursor
//               back on the next request (e.g. "after").
type CursorConfig struct {
	Type       string `mapstructure:"type"`
	Field      string `mapstructure:"field"`
	QueryParam string `mapstructure:"query_param"`
}

type SupplementaryConfig struct {
	Sources []SupplementarySourceConfig `mapstructure:"sources"`
}

type SupplementarySourceConfig struct {
	Enabled              bool          `mapstructure:"enabled"`
	Name                 string        `mapstructure:"name"`
	URL                  string        `mapstructure:"url"`
	APIKey               string        `mapstructure:"api_key"`
	PollInterval         time.Duration `mapstructure:"poll_interval"`
	BackfillEnabled      bool          `mapstructure:"backfill_enabled"`
	BackfillStartDate    string        `mapstructure:"backfill_start_date"`
	ResponseFieldMapping string        `mapstructure:"response_field_mapping"`
}

type HistoryConfig struct {
	StartDate         string `mapstructure:"start_date"`
	EndDate           string `mapstructure:"end_date"`
	BackfillOnStart   bool   `mapstructure:"backfill_on_start"`
	BatchDays         int    `mapstructure:"batch_days"`
	ConcurrentFetches int    `mapstructure:"concurrent_fetches"`
	ClickHouseURL     string `mapstructure:"clickhouse_url"`
	ClickHouseTable   string `mapstructure:"clickhouse_table"`
}

func Load() (*Config, error) {
	// Check if CONFIG_PATH is set for custom config file location
	if configPath := os.Getenv("CONFIG_PATH"); configPath != "" {
		viper.SetConfigFile(configPath)
	} else {
		viper.SetConfigName("config")
		viper.SetConfigType("yaml")
		viper.AddConfigPath(".")
		viper.AddConfigPath("/etc/rest-collector")
	}
	viper.AutomaticEnv()

	// Bind environment variables
	_ = viper.BindEnv("kafka.brokers", "KAFKA_BROKERS")
	_ = viper.BindEnv("kafka.topic", "KAFKA_TOPIC")
	_ = viper.BindEnv("kafka.supplementary_topic", "KAFKA_SUPPLEMENTARY_TOPIC")
	_ = viper.BindEnv("kafka.security_protocol", "KAFKA_SECURITY_PROTOCOL")
	_ = viper.BindEnv("kafka.sasl_mechanism", "KAFKA_SASL_MECHANISM")
	_ = viper.BindEnv("kafka.sasl_username", "KAFKA_SASL_USERNAME")
	_ = viper.BindEnv("kafka.sasl_password", "KAFKA_SASL_PASSWORD")
	_ = viper.BindEnv("kafka.ssl_ca_location", "KAFKA_SSL_CA_LOCATION")
	_ = viper.BindEnv("server.port", "SERVER_PORT")
	_ = viper.BindEnv("history.backfill_on_start", "HISTORY_BACKFILL_ON_START")
	_ = viper.BindEnv("history.start_date", "HISTORY_START_DATE")
	_ = viper.BindEnv("history.end_date", "HISTORY_END_DATE")
	_ = viper.BindEnv("history.clickhouse_url", "BACKFILL_CLICKHOUSE_URL")
	_ = viper.BindEnv("history.clickhouse_table", "BACKFILL_CLICKHOUSE_TABLE")
	_ = viper.BindEnv("polling.enabled", "POLLING_ENABLED")
	_ = viper.BindEnv("polling.historical_refresh_interval", "POLLING_HISTORICAL_REFRESH_INTERVAL")

	// Defaults
	viper.SetDefault("server.port", 8080)
	viper.SetDefault("kafka.brokers", []string{"platform-kafka-kafka-bootstrap.data-ingestion.svc.cluster.local:9092"})
	viper.SetDefault("kafka.topic", "ingested_data")
	viper.SetDefault("kafka.supplementary_topic", "supplementary_data")
	viper.SetDefault("kafka.batch_size", 100)
	viper.SetDefault("kafka.flush_timeout_ms", 1000)

	viper.SetDefault("polling.enabled", false)
	viper.SetDefault("polling.historical_refresh_interval", "60s")

	viper.SetDefault("history.start_date", "2025-01-01T00:00:00Z")
	viper.SetDefault("history.end_date", "")
	viper.SetDefault("history.backfill_on_start", true)
	viper.SetDefault("history.batch_days", 1)
	viper.SetDefault("history.concurrent_fetches", 4)

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); !ok {
			return nil, err
		}
	}

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, err
	}

	// Override Kafka brokers from env var if present (handles string format)
	if brokers := os.Getenv("KAFKA_BROKERS"); brokers != "" {
		cfg.Kafka.Brokers = strings.Split(brokers, ",")
	}

	// Build data sources from environment variables if none configured from file
	if len(cfg.DataSources) == 0 {
		cfg.DataSources = buildDataSourcesFromEnv()
	}

	// Build supplementary sources from environment variables if none configured from file
	if len(cfg.Supplementary.Sources) == 0 {
		cfg.Supplementary.Sources = buildSupplementarySourcesFromEnv()
	}

	return &cfg, nil
}

// buildDataSourcesFromEnv constructs data source configs from DATA_SOURCE_* env vars.
// Supports DATA_SOURCE_NAME, DATA_SOURCE_URL, DATA_SOURCE_SYMBOLS, etc.
func buildDataSourcesFromEnv() []DataSourceConfig {
	var sources []DataSourceConfig

	name := os.Getenv("DATA_SOURCE_NAME")
	url := os.Getenv("DATA_SOURCE_URL")
	if name != "" && url != "" {
		enabled := true
		if e := os.Getenv("DATA_SOURCE_ENABLED"); e != "" {
			enabled, _ = strconv.ParseBool(e)
		}
		symbols := []string{}
		if s := os.Getenv("DATA_SOURCE_SYMBOLS"); s != "" {
			symbols = strings.Split(s, ",")
		}
		granularity := 3600
		if g := os.Getenv("DATA_SOURCE_GRANULARITY"); g != "" {
			if v, err := strconv.Atoi(g); err == nil {
				granularity = v
			}
		}
		maxRecords := 300
		if m := os.Getenv("DATA_SOURCE_MAX_RECORDS"); m != "" {
			if v, err := strconv.Atoi(m); err == nil {
				maxRecords = v
			}
		}
		rateLimit := 150
		if r := os.Getenv("DATA_SOURCE_RATE_LIMIT_MS"); r != "" {
			if v, err := strconv.Atoi(r); err == nil {
				rateLimit = v
			}
		}
		sources = append(sources, DataSourceConfig{
			Enabled:     enabled,
			Name:        name,
			BaseURL:     url,
			Symbols:     symbols,
			Granularity: granularity,
			MaxRecords:  maxRecords,
			RateLimit:   rateLimit,
		})
	}

	return sources
}

// buildSupplementarySourcesFromEnv constructs supplementary source configs from env vars.
// Supports SUPPLEMENTARY_SOURCE_NAME, SUPPLEMENTARY_SOURCE_URL, etc.
func buildSupplementarySourcesFromEnv() []SupplementarySourceConfig {
	var sources []SupplementarySourceConfig

	name := os.Getenv("SUPPLEMENTARY_SOURCE_NAME")
	url := os.Getenv("SUPPLEMENTARY_SOURCE_URL")
	if name != "" && url != "" {
		enabled := true
		if e := os.Getenv("SUPPLEMENTARY_SOURCE_ENABLED"); e != "" {
			enabled, _ = strconv.ParseBool(e)
		}
		apiKey := os.Getenv("SUPPLEMENTARY_SOURCE_API_KEY")
		pollInterval := 5 * time.Minute
		if p := os.Getenv("SUPPLEMENTARY_SOURCE_POLL_INTERVAL"); p != "" {
			if d, err := time.ParseDuration(p); err == nil {
				pollInterval = d
			}
		}
		backfillEnabled, _ := strconv.ParseBool(os.Getenv("SUPPLEMENTARY_BACKFILL_ENABLED"))
		backfillStartDate := os.Getenv("SUPPLEMENTARY_BACKFILL_START_DATE")
		// If not set, fall back to HISTORY_START_DATE
		if backfillStartDate == "" {
			backfillStartDate = os.Getenv("HISTORY_START_DATE")
		}
		responseFieldMapping := os.Getenv("RESPONSE_FIELD_MAPPING")
		sources = append(sources, SupplementarySourceConfig{
			Enabled:              enabled,
			Name:                 name,
			URL:                  url,
			APIKey:               apiKey,
			PollInterval:         pollInterval,
			BackfillEnabled:      backfillEnabled,
			BackfillStartDate:    backfillStartDate,
			ResponseFieldMapping: responseFieldMapping,
		})
	}

	return sources
}
