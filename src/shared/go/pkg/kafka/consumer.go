package kafka

import (
	"context"
	"crypto/tls"
	"os"
	"strings"

	"github.com/multi-region-mall/shared/pkg/tracing"
	kafkago "github.com/segmentio/kafka-go"
	"github.com/segmentio/kafka-go/sasl/scram"
	"go.uber.org/zap"
)

type MessageHandler func(ctx context.Context, msg kafkago.Message) error

type Consumer struct {
	reader  *kafkago.Reader
	logger  *zap.Logger
	handler MessageHandler
}

func NewConsumer(brokers, topic, groupID string, handler MessageHandler, logger *zap.Logger) *Consumer {
	dialer := &kafkago.Dialer{
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
			dialer.SASLMechanism = mechanism
			logger.Info("SASL/SCRAM-SHA-512 authentication configured for Kafka consumer")
		}
	} else {
		logger.Info("No MSK_USERNAME/MSK_PASSWORD set for consumer, using TLS only")
	}

	// Use AZ-local brokers if KAFKA_BROKERS_LOCAL is set, otherwise use provided brokers
	effectiveBrokers := brokers
	if localBrokers := os.Getenv("KAFKA_BROKERS_LOCAL"); localBrokers != "" {
		effectiveBrokers = localBrokers
		logger.Info("Using AZ-local Kafka brokers", zap.String("brokers", localBrokers))
	}

	r := kafkago.NewReader(kafkago.ReaderConfig{
		Brokers:  strings.Split(effectiveBrokers, ","),
		Topic:    topic,
		GroupID:  groupID,
		MinBytes: 1,
		MaxBytes: 10e6,
		Dialer:   dialer,
		// NOTE: kafka-go v0.4.x does not support RackAffinityGroupBalancer.
		// Upgrade to a newer version to enable client.rack-based rack-aware consumption.
	})

	if clientRack := os.Getenv("CLIENT_RACK"); clientRack != "" {
		logger.Info("CLIENT_RACK is set but kafka-go v0.4.x lacks RackAffinityGroupBalancer support",
			zap.String("client_rack", clientRack))
	}

	return &Consumer{reader: r, logger: logger, handler: handler}
}

func (c *Consumer) Start(ctx context.Context) {
	c.logger.Info("starting consumer", zap.String("topic", c.reader.Config().Topic))
	for {
		select {
		case <-ctx.Done():
			return
		default:
			msg, err := c.reader.ReadMessage(ctx)
			if err != nil {
				if ctx.Err() != nil {
					return
				}
				c.logger.Error("read message failed", zap.Error(err))
				continue
			}
			msgCtx := tracing.ExtractKafkaHeaders(ctx, msg.Headers)
			if err := c.handler(msgCtx, msg); err != nil {
				c.logger.Error("handle message failed",
					zap.String("key", string(msg.Key)),
					zap.Error(err))
			}
		}
	}
}

func (c *Consumer) Close() error {
	return c.reader.Close()
}
