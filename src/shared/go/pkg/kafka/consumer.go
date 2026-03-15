package kafka

import (
	"context"
	"strings"

	"github.com/multi-region-mall/shared/pkg/tracing"
	kafkago "github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type MessageHandler func(ctx context.Context, msg kafkago.Message) error

type Consumer struct {
	reader  *kafkago.Reader
	logger  *zap.Logger
	handler MessageHandler
}

func NewConsumer(brokers, topic, groupID string, handler MessageHandler, logger *zap.Logger) *Consumer {
	r := kafkago.NewReader(kafkago.ReaderConfig{
		Brokers:  strings.Split(brokers, ","),
		Topic:    topic,
		GroupID:  groupID,
		MinBytes: 1,
		MaxBytes: 10e6,
	})
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
