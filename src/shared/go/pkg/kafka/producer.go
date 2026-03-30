package kafka

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"os"
	"strings"
	"time"

	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/segmentio/kafka-go"
	"github.com/segmentio/kafka-go/sasl/scram"
	"go.uber.org/zap"
)

type Producer struct {
	writer *kafka.Writer
	logger *zap.Logger
}

func NewProducer(brokers string, topic string, logger *zap.Logger) *Producer {
	transport := &kafka.Transport{
		TLS: &tls.Config{
			MinVersion: tls.VersionTLS12,
		},
	}

	// Configure SASL/SCRAM authentication if credentials are provided
	username := os.Getenv("MSK_USERNAME")
	password := os.Getenv("MSK_PASSWORD")
	if username != "" && password != "" {
		mechanism, err := scram.Mechanism(scram.SHA512, username, password)
		if err != nil {
			logger.Warn("failed to create SCRAM mechanism, proceeding without auth", zap.Error(err))
		} else {
			transport.SASL = mechanism
			logger.Info("SASL/SCRAM-SHA-512 authentication configured for Kafka")
		}
	} else {
		logger.Info("No MSK_USERNAME/MSK_PASSWORD set, using TLS only (IAM auth may apply)")
	}

	w := &kafka.Writer{
		Addr:         kafka.TCP(strings.Split(brokers, ",")...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		BatchTimeout: 10 * time.Millisecond,
		RequiredAcks: kafka.RequireAll,
		Transport:    transport,
	}
	return &Producer{writer: w, logger: logger}
}

func (p *Producer) Publish(ctx context.Context, key string, value interface{}) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}

	var headers []kafka.Header
	tracing.InjectKafkaHeaders(ctx, &headers)

	msg := kafka.Message{
		Key:     []byte(key),
		Value:   data,
		Time:    time.Now(),
		Headers: headers,
	}

	if err := p.writer.WriteMessages(ctx, msg); err != nil {
		p.logger.Error("failed to publish message", zap.String("key", key), zap.Error(err))
		return err
	}

	p.logger.Debug("published message", zap.String("topic", p.writer.Topic), zap.String("key", key))
	return nil
}

func (p *Producer) Close() error {
	return p.writer.Close()
}
