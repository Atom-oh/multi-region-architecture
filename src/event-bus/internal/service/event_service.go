package service

import (
	"context"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/multi-region-mall/event-bus/internal/model"
	"github.com/multi-region-mall/event-bus/internal/producer"
	"go.uber.org/zap"
)

var availableTopics = []string{
	"orders",
	"payments",
	"inventory",
	"users",
	"products",
	"cart",
	"shipping",
	"notifications",
	"reviews",
	"pricing",
	"analytics",
	"recommendations",
}

type EventService struct {
	producer *producer.EventProducer
	logger   *zap.Logger
	dlq      map[string]*model.DLQMessage
	dlqMu    sync.RWMutex
}

func NewEventService(producer *producer.EventProducer, logger *zap.Logger) *EventService {
	return &EventService{
		producer: producer,
		logger:   logger,
		dlq:      make(map[string]*model.DLQMessage),
	}
}

func (s *EventService) PublishEvent(ctx context.Context, topic, key string, payload interface{}) (*model.Event, error) {
	event := &model.Event{
		ID:        uuid.New().String(),
		Topic:     topic,
		Key:       key,
		Payload:   payload,
		Timestamp: time.Now().UTC(),
	}

	err := s.producer.Publish(ctx, topic, key, event)
	if err != nil {
		// Add to DLQ on failure
		s.addToDLQ(event, err.Error())
		return event, err
	}

	s.logger.Info("event published",
		zap.String("id", event.ID),
		zap.String("topic", topic),
		zap.String("key", key),
	)

	return event, nil
}

func (s *EventService) GetTopics() []string {
	return availableTopics
}

func (s *EventService) GetDLQMessages() []*model.DLQMessage {
	s.dlqMu.RLock()
	defer s.dlqMu.RUnlock()

	messages := make([]*model.DLQMessage, 0, len(s.dlq))
	for _, msg := range s.dlq {
		messages = append(messages, msg)
	}
	return messages
}

func (s *EventService) RetryDLQMessage(ctx context.Context, id string) (*model.Event, error) {
	s.dlqMu.Lock()
	msg, exists := s.dlq[id]
	if !exists {
		s.dlqMu.Unlock()
		return nil, model.ErrDLQMessageNotFound
	}
	delete(s.dlq, id)
	s.dlqMu.Unlock()

	event := &model.Event{
		ID:         msg.ID,
		Topic:      msg.Topic,
		Key:        msg.Key,
		Payload:    msg.Payload,
		Timestamp:  time.Now().UTC(),
		RetryCount: msg.RetryCount + 1,
	}

	err := s.producer.Publish(ctx, event.Topic, event.Key, event)
	if err != nil {
		// Re-add to DLQ with incremented retry count
		s.addToDLQWithRetry(event, err.Error(), event.RetryCount)
		return event, err
	}

	s.logger.Info("DLQ message retried successfully",
		zap.String("id", event.ID),
		zap.String("topic", event.Topic),
		zap.Int("retryCount", event.RetryCount),
	)

	return event, nil
}

func (s *EventService) addToDLQ(event *model.Event, errMsg string) {
	s.addToDLQWithRetry(event, errMsg, 0)
}

func (s *EventService) addToDLQWithRetry(event *model.Event, errMsg string, retryCount int) {
	s.dlqMu.Lock()
	defer s.dlqMu.Unlock()

	s.dlq[event.ID] = &model.DLQMessage{
		ID:         event.ID,
		Topic:      event.Topic,
		Key:        event.Key,
		Payload:    event.Payload,
		Error:      errMsg,
		Timestamp:  time.Now().UTC(),
		RetryCount: retryCount,
	}

	s.logger.Warn("event added to DLQ",
		zap.String("id", event.ID),
		zap.String("topic", event.Topic),
		zap.String("error", errMsg),
		zap.Int("retryCount", retryCount),
	)
}
