// Package producer implements Kafka message producer
// Batches and sends data records to Kafka topics
package producer

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/mlops-platform/rest-collector/config"
	"github.com/mlops-platform/rest-collector/internal/collector"
	"github.com/xdg-go/scram"
	"go.uber.org/zap"
)

// SCRAM client glue for sarama — sarama only ships the interface; we wire in
// xdg-go/scram. Same pattern used across the IBM/sarama community for
// SASL_SSL + SCRAM-SHA-512 (Strimzi default).
var (
	sha512ClientGen scram.HashGeneratorFcn = func() scram.HashGeneratorFcn { return scram.SHA512 }()
	sha256ClientGen scram.HashGeneratorFcn = func() scram.HashGeneratorFcn { return scram.SHA256 }()
)

type xdgSCRAMClient struct {
	*scram.Client
	*scram.ClientConversation
	scram.HashGeneratorFcn
}

func (x *xdgSCRAMClient) Begin(userName, password, authzID string) error {
	c, err := x.HashGeneratorFcn.NewClient(userName, password, authzID)
	if err != nil {
		return err
	}
	x.Client = c
	x.ClientConversation = x.Client.NewConversation()
	return nil
}

func (x *xdgSCRAMClient) Step(challenge string) (string, error) {
	return x.ClientConversation.Step(challenge)
}

func (x *xdgSCRAMClient) Done() bool { return x.ClientConversation.Done() }

// KafkaProducer sends records to Kafka
type KafkaProducer struct {
	producer  sarama.SyncProducer
	topic     string
	sentTopic string
	logger    *zap.Logger
}

// NewKafkaProducer creates a new Kafka producer
func NewKafkaProducer(cfg config.KafkaConfig, logger *zap.Logger) (*KafkaProducer, error) {
	saramaCfg := sarama.NewConfig()
	saramaCfg.Producer.RequiredAcks = sarama.WaitForLocal
	saramaCfg.Producer.Compression = sarama.CompressionLZ4
	saramaCfg.Producer.Flush.Frequency = time.Duration(cfg.FlushTimeout) * time.Millisecond
	saramaCfg.Producer.Flush.Messages = cfg.BatchSize
	saramaCfg.Producer.Return.Successes = true

	if err := applyKafkaSecurity(saramaCfg, cfg, logger); err != nil {
		return nil, err
	}

	producer, err := sarama.NewSyncProducer(cfg.Brokers, saramaCfg)
	if err != nil {
		return nil, err
	}

	return &KafkaProducer{
		producer:  producer,
		topic:     cfg.Topic,
		sentTopic: cfg.SentTopic,
		logger:    logger,
	}, nil
}

// applyKafkaSecurity wires SASL+TLS into sarama from KafkaConfig. Mirrors the
// platform pipeline-config / crypto-app-consumer envFrom contract:
//
//	KAFKA_SECURITY_PROTOCOL = SASL_SSL  → enable both
//	KAFKA_SASL_MECHANISM    = SCRAM-SHA-512 (or SCRAM-SHA-256 / PLAIN)
//	KAFKA_SASL_USERNAME / KAFKA_SASL_PASSWORD → SCRAM creds
//	KAFKA_SSL_CA_LOCATION   = /etc/kafka/ca/ca.crt → broker CA truststore
//
// PLAINTEXT (platform default :9092) stays the no-op fall-through.
func applyKafkaSecurity(saramaCfg *sarama.Config, cfg config.KafkaConfig, logger *zap.Logger) error {
	proto := strings.ToUpper(strings.TrimSpace(cfg.SecurityProtocol))
	if proto == "" || proto == "PLAINTEXT" {
		return nil
	}

	wantTLS := proto == "SSL" || proto == "SASL_SSL"
	wantSASL := proto == "SASL_PLAINTEXT" || proto == "SASL_SSL"

	if wantTLS {
		tlsCfg := &tls.Config{MinVersion: tls.VersionTLS12}
		if cfg.SSLCALocation != "" {
			caPEM, err := os.ReadFile(cfg.SSLCALocation)
			if err != nil {
				return fmt.Errorf("read kafka CA %q: %w", cfg.SSLCALocation, err)
			}
			pool := x509.NewCertPool()
			if !pool.AppendCertsFromPEM(caPEM) {
				return fmt.Errorf("parse kafka CA %q: no PEM blocks", cfg.SSLCALocation)
			}
			tlsCfg.RootCAs = pool
		}
		saramaCfg.Net.TLS.Enable = true
		saramaCfg.Net.TLS.Config = tlsCfg
		logger.Info("Kafka TLS enabled", zap.String("ca", cfg.SSLCALocation))
	}

	if wantSASL {
		mech := strings.ToUpper(strings.TrimSpace(cfg.SASLMechanism))
		saramaCfg.Net.SASL.Enable = true
		saramaCfg.Net.SASL.User = cfg.SASLUsername
		saramaCfg.Net.SASL.Password = cfg.SASLPassword
		saramaCfg.Net.SASL.Handshake = true
		switch mech {
		case "", "SCRAM-SHA-512":
			saramaCfg.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA512
			saramaCfg.Net.SASL.SCRAMClientGeneratorFunc = func() sarama.SCRAMClient {
				return &xdgSCRAMClient{HashGeneratorFcn: sha512ClientGen}
			}
		case "SCRAM-SHA-256":
			saramaCfg.Net.SASL.Mechanism = sarama.SASLTypeSCRAMSHA256
			saramaCfg.Net.SASL.SCRAMClientGeneratorFunc = func() sarama.SCRAMClient {
				return &xdgSCRAMClient{HashGeneratorFcn: sha256ClientGen}
			}
		case "PLAIN":
			saramaCfg.Net.SASL.Mechanism = sarama.SASLTypePlaintext
		default:
			return fmt.Errorf("unsupported SASL mechanism %q (want SCRAM-SHA-512|SCRAM-SHA-256|PLAIN)", mech)
		}
		logger.Info("Kafka SASL enabled",
			zap.String("mechanism", string(saramaCfg.Net.SASL.Mechanism)),
			zap.String("user", cfg.SASLUsername))
	}

	return nil
}

// SendRecords sends data records to Kafka
func (p *KafkaProducer) SendRecords(records []collector.Record) error {
	messages := make([]*sarama.ProducerMessage, len(records))

	for i, record := range records {
		data, err := json.Marshal(record)
		if err != nil {
			p.logger.Error("Failed to marshal record", zap.Error(err))
			continue
		}

		messages[i] = &sarama.ProducerMessage{
			Topic: p.topic,
			Key:   sarama.StringEncoder(record.Symbol),
			Value: sarama.ByteEncoder(data),
		}
	}

	err := p.producer.SendMessages(messages)
	if err != nil {
		return err
	}

	p.logger.Debug("Sent records", zap.Int("count", len(records)))
	return nil
}

// SendRecordsToTopic sends records to a specific Kafka topic
func (p *KafkaProducer) SendRecordsToTopic(topic string, records []collector.Record) error {
	if topic == "" {
		return p.SendRecords(records)
	}
	messages := make([]*sarama.ProducerMessage, len(records))

	for i, record := range records {
		data, err := json.Marshal(record)
		if err != nil {
			p.logger.Error("Failed to marshal record", zap.Error(err))
			continue
		}

		messages[i] = &sarama.ProducerMessage{
			Topic: topic,
			Key:   sarama.StringEncoder(record.Symbol),
			Value: sarama.ByteEncoder(data),
		}
	}

	err := p.producer.SendMessages(messages)
	if err != nil {
		return err
	}

	p.logger.Debug("Sent records to topic", zap.String("topic", topic), zap.Int("count", len(records)))
	return nil
}

// SupplementaryRecord represents supplementary data
type SupplementaryRecord struct {
	Source    string    `json:"source"`
	Timestamp time.Time `json:"timestamp"`
	Title     string    `json:"title,omitempty"`
	Score     float64   `json:"score"`
	Symbol    string    `json:"symbol,omitempty"`
	URL       string    `json:"url,omitempty"`
}

// SendSupplementary sends supplementary records to Kafka
func (p *KafkaProducer) SendSupplementary(records []SupplementaryRecord) error {
	messages := make([]*sarama.ProducerMessage, len(records))

	for i, record := range records {
		data, err := json.Marshal(record)
		if err != nil {
			p.logger.Error("Failed to marshal supplementary record", zap.Error(err))
			continue
		}

		key := record.Source
		if record.Symbol != "" {
			key = record.Symbol
		}

		messages[i] = &sarama.ProducerMessage{
			Topic: p.sentTopic,
			Key:   sarama.StringEncoder(key),
			Value: sarama.ByteEncoder(data),
		}
	}

	err := p.producer.SendMessages(messages)
	if err != nil {
		return err
	}

	p.logger.Debug("Sent supplementary records", zap.Int("count", len(records)))
	return nil
}

// Close closes the producer
func (p *KafkaProducer) Close() error {
	return p.producer.Close()
}
