// REST Collector for historical and supplementary data
// Go service optimized for HTTP API calls with <5ms latency
// Collects from configurable REST data sources and supplementary HTTP sources
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/mlops-platform/rest-collector/config"
	"github.com/mlops-platform/rest-collector/internal/collector"
	"github.com/mlops-platform/rest-collector/internal/health"
	"github.com/mlops-platform/rest-collector/internal/producer"
	"github.com/mlops-platform/rest-collector/internal/supplementary"
	"go.uber.org/zap"
)

func main() {
	// Parse flags
	once := flag.Bool("once", false, "Run one-shot mode: fetch supplementary/backfill once and exit (for CronJob use)")
	flag.Parse()

	// Initialize logger
	logger, _ := zap.NewProduction()
	defer func() { _ = logger.Sync() }()

	logger.Info("Starting REST Collector", zap.Bool("once", *once))

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		logger.Fatal("Failed to load config", zap.Error(err))
	}

	// Create Kafka producer
	prod, err := producer.NewKafkaProducer(cfg.Kafka, logger)
	if err != nil {
		logger.Fatal("Failed to create Kafka producer", zap.Error(err))
	}
	defer func() { _ = prod.Close() }()

	// Context for graceful shutdown
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var wg sync.WaitGroup

	// In one-shot mode, skip the health server and polling loop —
	// just run supplementary/backfill fetches and exit.
	if *once {
		logger.Info("One-shot mode: running supplementary/backfill fetch")

		// Backfill historical data if enabled
		if cfg.History.BackfillOnStart {
			wg.Add(1)
			go func() {
				defer wg.Done()
				backfillHistorical(ctx, cfg, prod, logger)
			}()
		}

		// Run supplementary sources with PollInterval=0 (one-shot)
		for i := range cfg.Supplementary.Sources {
			src := cfg.Supplementary.Sources[i]
			if src.Enabled {
				// Force one-shot by clearing the poll interval
				src.PollInterval = 0
				httpSource := supplementary.NewHTTPSourceCollector(
					src,
					prod,
					logger,
				)
				wg.Add(1)
				go func() {
					defer wg.Done()
					httpSource.Run(ctx)
				}()
			}
		}

		wg.Wait()
		logger.Info("One-shot mode complete")
		return
	}

	// --- Long-running server mode ---

	// Start health server
	healthServer := health.NewServer()
	wg.Add(1)
	go func() {
		defer wg.Done()
		addr := fmt.Sprintf(":%d", cfg.Server.Port)
		logger.Info("Starting health server", zap.String("addr", addr))
		if err := healthServer.Run(addr); err != nil {
			logger.Error("Health server error", zap.Error(err))
		}
	}()

	// Backfill historical data if enabled
	if cfg.History.BackfillOnStart {
		wg.Add(1)
		go func() {
			defer wg.Done()
			backfillHistorical(ctx, cfg, prod, logger)
		}()
	}

	// Start periodic polling for latest data
	if cfg.Polling.Enabled {
		wg.Add(1)
		go func() {
			defer wg.Done()
			runPollingLoop(ctx, cfg, prod, logger)
		}()
	}

	// Start supplementary data collectors
	for i := range cfg.Supplementary.Sources {
		src := cfg.Supplementary.Sources[i]
		if src.Enabled {
			httpSource := supplementary.NewHTTPSourceCollector(
				src,
				prod,
				logger,
			)
			wg.Add(1)
			go func() {
				defer wg.Done()
				httpSource.Run(ctx)
			}()
		}
	}

	// Wait for shutdown signal
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh

	logger.Info("Shutting down")
	cancel()
	wg.Wait()
	logger.Info("Shutdown complete")
}

// queryClickHouseMaxTimestamp queries ClickHouse for the latest data timestamp per symbol.
// Returns zero time if no data exists or ClickHouse is unreachable.
func queryClickHouseMaxTimestamp(chURL, table, symbol string, logger *zap.Logger) time.Time {
	if chURL == "" || table == "" {
		return time.Time{}
	}

	query := fmt.Sprintf(
		"SELECT max(timestamp) FROM %s WHERE symbol = '%s' FORMAT TabSeparated",
		table, symbol,
	)

	reqURL := fmt.Sprintf("%s/?query=%s", chURL, url.QueryEscape(query))
	resp, err := http.Get(reqURL)
	if err != nil {
		logger.Debug("ClickHouse query failed (will do full backfill)", zap.Error(err))
		return time.Time{}
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		logger.Debug("ClickHouse returned non-200 (will do full backfill)",
			zap.Int("status", resp.StatusCode))
		return time.Time{}
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return time.Time{}
	}

	tsStr := strings.TrimSpace(string(body))
	if tsStr == "" || tsStr == "0000-00-00 00:00:00.000" || tsStr == "1970-01-01 00:00:00.000" {
		return time.Time{}
	}

	// ClickHouse DateTime64(3) format: "2026-03-14 23:00:00.000"
	for _, layout := range []string{
		"2006-01-02 15:04:05.000",
		"2006-01-02 15:04:05",
		time.RFC3339,
	} {
		if t, err := time.Parse(layout, tsStr); err == nil {
			return t
		}
	}

	logger.Debug("Could not parse ClickHouse timestamp", zap.String("raw", tsStr))
	return time.Time{}
}

// backfillHistorical fetches historical data on startup with smart gap detection.
// It checks ClickHouse for the latest data timestamp per symbol:
//   - If data exists, backfills from last timestamp to now (gap-fill)
//   - If no data, backfills from HISTORY_START_DATE to now
func backfillHistorical(
	ctx context.Context,
	cfg *config.Config,
	prod *producer.KafkaProducer,
	logger *zap.Logger,
) {
	defaultStart, err := time.Parse(time.RFC3339, cfg.History.StartDate)
	if err != nil {
		logger.Error("Invalid start date", zap.Error(err))
		return
	}

	// End date is always "now" — ignore HISTORY_END_DATE if empty
	endDate := time.Now().UTC()
	if cfg.History.EndDate != "" {
		if parsed, err := time.Parse(time.RFC3339, cfg.History.EndDate); err == nil {
			endDate = parsed
		}
	}

	logger.Info("Smart backfill: checking ClickHouse for existing data",
		zap.String("clickhouse_url", cfg.History.ClickHouseURL),
		zap.String("table", cfg.History.ClickHouseTable),
		zap.Time("default_start", defaultStart),
		zap.Time("end", endDate))

	// Iterate over configured data sources
	for i := range cfg.DataSources {
		src := cfg.DataSources[i]
		if !src.Enabled {
			continue
		}

		restSource := collector.NewRESTSourceCollector(src, logger)
		for _, symbol := range src.Symbols {
			select {
			case <-ctx.Done():
				return
			default:
			}

			// Smart gap detection: check ClickHouse for latest data
			startDate := defaultStart
			lastTS := queryClickHouseMaxTimestamp(
				cfg.History.ClickHouseURL,
				cfg.History.ClickHouseTable,
				symbol,
				logger,
			)
			if !lastTS.IsZero() {
				// Data exists — backfill from last timestamp (with 1 candle overlap for safety)
				gapStart := lastTS.Add(-time.Duration(src.Granularity) * time.Second)
				if gapStart.After(defaultStart) {
					startDate = gapStart
				}
				logger.Info("Gap-fill: found existing data",
					zap.String("symbol", symbol),
					zap.Time("last_data", lastTS),
					zap.Time("backfill_from", startDate))
			} else {
				logger.Info("No existing data found, full backfill",
					zap.String("symbol", symbol),
					zap.Time("backfill_from", startDate))
			}

			// Skip if start >= end (data is already up to date)
			if !startDate.Before(endDate) {
				logger.Info("Data already up to date, skipping backfill",
					zap.String("symbol", symbol))
				health.BackfillProgress.WithLabelValues(symbol).Set(1.0)
				continue
			}

			logger.Info("Backfilling data source",
				zap.String("source", src.Name),
				zap.String("symbol", symbol),
				zap.Time("from", startDate),
				zap.Time("to", endDate))

			records, err := restSource.FetchHistorical(symbol, startDate, endDate)
			if err != nil {
				logger.Error("Backfill failed",
					zap.String("source", src.Name),
					zap.String("symbol", symbol),
					zap.Error(err))
				health.FetchErrors.WithLabelValues(src.Name).Inc()
				continue
			}

			// Send in batches
			batchSize := 100
			for i := 0; i < len(records); i += batchSize {
				end := i + batchSize
				if end > len(records) {
					end = len(records)
				}

				if err := prod.SendRecords(records[i:end]); err != nil {
					logger.Error("Failed to send batch", zap.Error(err))
				}

				progress := float64(end) / float64(len(records))
				health.BackfillProgress.WithLabelValues(symbol).Set(progress)
			}

			health.RecordsFetched.WithLabelValues(src.Name, symbol).Add(float64(len(records)))
			health.BackfillProgress.WithLabelValues(symbol).Set(1.0)
		}
	}

	logger.Info("Historical backfill complete")
}

// runPollingLoop fans out two poll families:
//
//   1. A single "historical refresh" loop per data source/symbol that
//      re-fetches the latest window via FetchHistorical at
//      cfg.Polling.HistoricalRefreshInterval. This keeps the
//      time-series up to date without re-running the full backfill.
//
//   2. One dedicated goroutine per (data_source, endpoint, symbol)
//      triple for every EndpointConfig entry. Each goroutine owns its
//      own ticker (endpoint.PollInterval), cursor state, and target
//      Kafka topic, so endpoint cadences remain independent.
//
// No endpoint-specific logic lives in this function — every remote
// API shape is expressed via EndpointConfig.
func runPollingLoop(
	ctx context.Context,
	cfg *config.Config,
	prod *producer.KafkaProducer,
	logger *zap.Logger,
) {
	logger.Info("Starting periodic polling loop",
		zap.Duration("historical_refresh_interval", cfg.Polling.HistoricalRefreshInterval),
		zap.Int("data_sources", len(cfg.DataSources)))

	var wg sync.WaitGroup

	for i := range cfg.DataSources {
		src := cfg.DataSources[i]
		if !src.Enabled {
			continue
		}

		// Historical refresh: one goroutine per data source covering all symbols.
		wg.Add(1)
		go func(src config.DataSourceConfig) {
			defer wg.Done()
			runHistoricalRefresh(ctx, src, cfg.Polling.HistoricalRefreshInterval, prod, logger)
		}(src)

		// Per-endpoint polling: one goroutine per (endpoint, symbol).
		for j := range src.Endpoints {
			ep := src.Endpoints[j]
			if !ep.Enabled {
				continue
			}
			if ep.PollInterval <= 0 {
				logger.Warn("Endpoint has non-positive poll_interval, skipping",
					zap.String("source", src.Name),
					zap.String("endpoint", ep.Name))
				continue
			}
			for _, symbol := range src.Symbols {
				wg.Add(1)
				go func(src config.DataSourceConfig, ep config.EndpointConfig, symbol string) {
					defer wg.Done()
					runEndpointLoop(ctx, src, ep, symbol, cfg.Kafka.Topic, prod, logger)
				}(src, ep, symbol)
			}
		}
	}

	<-ctx.Done()
	logger.Info("Polling loop shutting down, waiting for workers")
	wg.Wait()
	logger.Info("Polling loop stopped")
}

// runHistoricalRefresh re-fetches the latest window from the historical
// endpoint for each symbol on a fixed cadence.
func runHistoricalRefresh(
	ctx context.Context,
	src config.DataSourceConfig,
	interval time.Duration,
	prod *producer.KafkaProducer,
	logger *zap.Logger,
) {
	if interval <= 0 {
		logger.Info("Historical refresh disabled (non-positive interval)",
			zap.String("source", src.Name))
		return
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	restSource := collector.NewRESTSourceCollector(src, logger)
	lastTime := make(map[string]time.Time, len(src.Symbols))

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			for _, symbol := range src.Symbols {
				records, err := restSource.FetchSince(symbol, lastTime[symbol])
				if err != nil {
					logger.Warn("Historical refresh failed",
						zap.String("source", src.Name),
						zap.String("symbol", symbol),
						zap.Error(err))
					health.FetchErrors.WithLabelValues(src.Name).Inc()
					continue
				}
				if len(records) == 0 {
					continue
				}
				if err := prod.SendRecords(records); err != nil {
					logger.Error("Failed to send historical refresh batch", zap.Error(err))
					continue
				}
				lastTime[symbol] = records[len(records)-1].Timestamp
				health.RecordsFetched.WithLabelValues(src.Name, symbol).Add(float64(len(records)))
				logger.Debug("Historical refresh sent",
					zap.String("source", src.Name),
					zap.String("symbol", symbol),
					zap.Int("count", len(records)))
			}
		}
	}
}

// runEndpointLoop drives a single (data_source, endpoint, symbol) poll
// loop using the endpoint's own cadence, cursor state, and Kafka topic.
func runEndpointLoop(
	ctx context.Context,
	src config.DataSourceConfig,
	ep config.EndpointConfig,
	symbol string,
	defaultTopic string,
	prod *producer.KafkaProducer,
	logger *zap.Logger,
) {
	logger.Info("Starting endpoint poll loop",
		zap.String("source", src.Name),
		zap.String("endpoint", ep.Name),
		zap.String("symbol", symbol),
		zap.Duration("poll_interval", ep.PollInterval))

	ticker := time.NewTicker(ep.PollInterval)
	defer ticker.Stop()

	restSource := collector.NewRESTSourceCollector(src, logger)
	state := collector.EndpointState{}
	topic := ep.KafkaTopic
	if topic == "" {
		topic = defaultTopic
	}

	for {
		select {
		case <-ctx.Done():
			logger.Info("Endpoint loop stopped",
				zap.String("endpoint", ep.Name),
				zap.String("symbol", symbol))
			return
		case <-ticker.C:
			records, newState, err := restSource.FetchEndpoint(ep, symbol, state)
			if err != nil {
				logger.Warn("Endpoint poll failed",
					zap.String("source", src.Name),
					zap.String("endpoint", ep.Name),
					zap.String("symbol", symbol),
					zap.Error(err))
				health.FetchErrors.WithLabelValues(src.Name).Inc()
				continue
			}
			state = newState
			if len(records) == 0 {
				continue
			}
			if err := prod.SendRecordsToTopic(topic, records); err != nil {
				logger.Error("Failed to send endpoint records",
					zap.String("endpoint", ep.Name),
					zap.Error(err))
				continue
			}
			health.RecordsFetched.WithLabelValues(src.Name, symbol).Add(float64(len(records)))
			logger.Debug("Endpoint poll sent",
				zap.String("endpoint", ep.Name),
				zap.String("symbol", symbol),
				zap.Int("count", len(records)))
		}
	}
}
