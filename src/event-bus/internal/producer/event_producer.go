package producer

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
	"go.uber.org/zap"
)

type EventProducer struct {
	brokers string
	writers map[string]*kafka.Writer
	logger  *zap.Logger
}

func NewEventProducer(brokers string, logger *zap.Logger) *EventProducer {
	return &EventProducer{
		brokers: brokers,
		writers: make(map[string]*kafka.Writer),
		logger:  logger,
	}
}

func (p *EventProducer) getWriter(topic string) *kafka.Writer {
	if w, exists := p.writers[topic]; exists {
		return w
	}

	w := &kafka.Writer{
		Addr:         kafka.TCP(strings.Split(p.brokers, ",")...),
		Topic:        topic,
		Balancer:     &kafka.LeastBytes{},
		BatchTimeout: 10 * time.Millisecond,
		RequiredAcks: kafka.RequireAll,
	}
	p.writers[topic] = w
	return w
}

func (p *EventProducer) Publish(ctx context.Context, topic, key string, value interface{}) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}

	writer := p.getWriter(topic)
	msg := kafka.Message{
		Key:   []byte(key),
		Value: data,
		Time:  time.Now(),
	}

	if err := writer.WriteMessages(ctx, msg); err != nil {
		p.logger.Error("failed to publish message",
			zap.String("topic", topic),
			zap.String("key", key),
			zap.Error(err),
		)
		return err
	}

	p.logger.Debug("published message",
		zap.String("topic", topic),
		zap.String("key", key),
	)
	return nil
}

func (p *EventProducer) Close() {
	for topic, writer := range p.writers {
		if err := writer.Close(); err != nil {
			p.logger.Error("failed to close writer", zap.String("topic", topic), zap.Error(err))
		}
	}
}
