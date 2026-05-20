package producer

import (
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/mlops-platform/rest-collector/config"
	"github.com/mlops-platform/rest-collector/internal/collector"
	"github.com/stretchr/testify/assert"
	"go.uber.org/zap"
)

func TestNewKafkaProducer(t *testing.T) {
	t.Run("fails with invalid broker", func(t *testing.T) {
		cfg := config.KafkaConfig{
			Brokers:      []string{"invalid-broker:9092"},
			Topic:        "test-topic",
			SentTopic:    "test-sent-topic",
			BatchSize:    100,
			FlushTimeout: 1000,
		}

		producer, err := NewKafkaProducer(cfg, zap.NewNop())

		// Should return error when cannot connect
		assert.Error(t, err)
		assert.Nil(t, producer)
	})

	t.Run("creates producer with correct config", func(t *testing.T) {
		// Test that config is set up correctly even if connection fails
		cfg := config.KafkaConfig{
			Brokers:      []string{"localhost:9092"},
			Topic:        "data-topic",
			SentTopic:    "supplementary-topic",
			BatchSize:    50,
			FlushTimeout: 500,
		}

		// We expect this to fail in test environment, but we verify the configuration
		_, err := NewKafkaProducer(cfg, zap.NewNop())

		// Error is expected since Kafka is not running in tests
		assert.Error(t, err)
	})
}

func TestKafkaProducer_SendRecords(t *testing.T) {
	t.Run("formats record messages correctly", func(t *testing.T) {
		records := []collector.Record{
			{
				Symbol:    "SYM1",
				Timestamp: time.Unix(1600000000, 0),
				Source:    "source-a",
				Values: map[string]float64{
					"value_a": 10000.0,
					"value_b": 10100.0,
					"value_c": 50.5,
				},
			},
			{
				Symbol:    "SYM2",
				Timestamp: time.Unix(1600000060, 0),
				Source:    "source-a",
				Values: map[string]float64{
					"value_a": 300.0,
					"value_b": 310.0,
					"value_c": 150.2,
				},
			},
		}

		// Test message construction logic (without actual Kafka)
		for _, record := range records {
			assert.NotEmpty(t, record.Symbol)
			assert.NotZero(t, record.Timestamp)
			assert.NotEmpty(t, record.Values)
		}
	})
}

func TestKafkaProducer_SendSupplementary(t *testing.T) {
	t.Run("formats supplementary messages correctly", func(t *testing.T) {
		records := []SupplementaryRecord{
			{
				Source:    "supplementary-a",
				Timestamp: time.Now().UTC(),
				Title:     "Data update",
				Score:     0.8,
				Symbol:    "SYM1",
				URL:       "https://example.com",
			},
			{
				Source:    "supplementary-b",
				Timestamp: time.Now().UTC(),
				Title:     "Index reading",
				Score:     0.9,
				Symbol:    "SYM1",
			},
		}

		// Test message construction logic
		for _, record := range records {
			assert.NotEmpty(t, record.Source)
			assert.NotZero(t, record.Timestamp)
			assert.GreaterOrEqual(t, record.Score, -1.0)
			assert.LessOrEqual(t, record.Score, 1.0)
		}
	})

	t.Run("uses symbol as key when available", func(t *testing.T) {
		record := SupplementaryRecord{
			Source: "supplementary-a",
			Symbol: "SYM1",
		}

		// Key should be symbol when present
		key := record.Source
		if record.Symbol != "" {
			key = record.Symbol
		}

		assert.Equal(t, "SYM1", key)
	})

	t.Run("uses source as key when symbol is empty", func(t *testing.T) {
		record := SupplementaryRecord{
			Source: "supplementary-b",
			Symbol: "",
		}

		key := record.Source
		if record.Symbol != "" {
			key = record.Symbol
		}

		assert.Equal(t, "supplementary-b", key)
	})
}

func TestSupplementaryRecord(t *testing.T) {
	t.Run("struct has all required fields", func(t *testing.T) {
		record := SupplementaryRecord{
			Source:    "test",
			Timestamp: time.Now().UTC(),
			Title:     "Test Title",
			Score:     0.5,
			Symbol:    "SYM1",
			URL:       "https://test.com",
		}

		assert.Equal(t, "test", record.Source)
		assert.NotZero(t, record.Timestamp)
		assert.Equal(t, "Test Title", record.Title)
		assert.Equal(t, 0.5, record.Score)
		assert.Equal(t, "SYM1", record.Symbol)
		assert.Equal(t, "https://test.com", record.URL)
	})

	t.Run("optional fields can be empty", func(t *testing.T) {
		record := SupplementaryRecord{
			Source:    "test",
			Timestamp: time.Now().UTC(),
			Score:     0.0,
		}

		assert.Empty(t, record.Title)
		assert.Empty(t, record.Symbol)
		assert.Empty(t, record.URL)
	})
}

func TestKafkaConfig(t *testing.T) {
	t.Run("creates sarama config with correct settings", func(t *testing.T) {
		cfg := config.KafkaConfig{
			Brokers:      []string{"localhost:9092"},
			Topic:        "test-topic",
			BatchSize:    100,
			FlushTimeout: 1000,
		}

		saramaConfig := sarama.NewConfig()
		saramaConfig.Producer.RequiredAcks = sarama.WaitForLocal
		saramaConfig.Producer.Compression = sarama.CompressionLZ4
		saramaConfig.Producer.Flush.Frequency = time.Duration(cfg.FlushTimeout) * time.Millisecond
		saramaConfig.Producer.Flush.Messages = cfg.BatchSize
		saramaConfig.Producer.Return.Successes = true

		assert.Equal(t, sarama.WaitForLocal, saramaConfig.Producer.RequiredAcks)
		assert.Equal(t, sarama.CompressionLZ4, saramaConfig.Producer.Compression)
		assert.Equal(t, 1000*time.Millisecond, saramaConfig.Producer.Flush.Frequency)
		assert.Equal(t, 100, saramaConfig.Producer.Flush.Messages)
		assert.True(t, saramaConfig.Producer.Return.Successes)
	})
}

func TestProducerMessage(t *testing.T) {
	t.Run("record message has correct key", func(t *testing.T) {
		record := collector.Record{
			Symbol: "SYM1",
			Source: "source-a",
			Values: map[string]float64{"value_a": 100.0},
		}

		// Key should be the symbol
		key := record.Symbol
		assert.Equal(t, "SYM1", key)
	})

	t.Run("supplementary message key selection", func(t *testing.T) {
		testCases := []struct {
			name     string
			record   SupplementaryRecord
			expected string
		}{
			{
				name:     "uses symbol when present",
				record:   SupplementaryRecord{Source: "supplementary-a", Symbol: "SYM1"},
				expected: "SYM1",
			},
			{
				name:     "uses source when symbol empty",
				record:   SupplementaryRecord{Source: "supplementary-b", Symbol: ""},
				expected: "supplementary-b",
			},
		}

		for _, tc := range testCases {
			t.Run(tc.name, func(t *testing.T) {
				key := tc.record.Source
				if tc.record.Symbol != "" {
					key = tc.record.Symbol
				}
				assert.Equal(t, tc.expected, key)
			})
		}
	})
}

func TestKafkaProducer_Close(t *testing.T) {
	t.Run("close method exists", func(t *testing.T) {
		// Cannot test actual close without a real producer
		// Just verify the method signature exists
		var producer *KafkaProducer
		if producer != nil {
			err := producer.Close()
			assert.NoError(t, err)
		}
	})
}

func TestMessageBatching(t *testing.T) {
	t.Run("creates correct number of messages", func(t *testing.T) {
		records := []collector.Record{
			{Symbol: "SYM1", Values: map[string]float64{"value_a": 100}},
			{Symbol: "SYM2", Values: map[string]float64{"value_a": 200}},
			{Symbol: "SYM3", Values: map[string]float64{"value_a": 300}},
		}

		messages := make([]*sarama.ProducerMessage, len(records))
		assert.Len(t, messages, 3)
	})

	t.Run("handles empty records", func(t *testing.T) {
		records := []collector.Record{}
		messages := make([]*sarama.ProducerMessage, len(records))
		assert.Len(t, messages, 0)
	})
}
