package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/event-bus/internal/model"
	"github.com/multi-region-mall/event-bus/internal/service"
	"go.uber.org/zap"
)

type EventsHandler struct {
	service *service.EventService
	logger  *zap.Logger
}

func NewEventsHandler(svc *service.EventService, logger *zap.Logger) *EventsHandler {
	return &EventsHandler{
		service: svc,
		logger:  logger,
	}
}

type PublishRequest struct {
	Topic   string      `json:"topic" binding:"required"`
	Key     string      `json:"key"`
	Payload interface{} `json:"payload" binding:"required"`
}

func (h *EventsHandler) PublishEvent(c *gin.Context) {
	var req PublishRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	event, err := h.service.PublishEvent(c.Request.Context(), req.Topic, req.Key, req.Payload)
	if err != nil {
		h.logger.Error("failed to publish event", zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to publish event"})
		return
	}

	c.JSON(http.StatusAccepted, gin.H{
		"id":        event.ID,
		"topic":     event.Topic,
		"timestamp": event.Timestamp,
	})
}

func (h *EventsHandler) ListTopics(c *gin.Context) {
	topics := h.service.GetTopics()
	c.JSON(http.StatusOK, gin.H{"topics": topics})
}

func (h *EventsHandler) ListDLQ(c *gin.Context) {
	dlqMessages := h.service.GetDLQMessages()
	c.JSON(http.StatusOK, gin.H{
		"messages": dlqMessages,
		"count":    len(dlqMessages),
	})
}

func (h *EventsHandler) RetryDLQ(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message id required"})
		return
	}

	event, err := h.service.RetryDLQMessage(c.Request.Context(), id)
	if err != nil {
		if err == model.ErrDLQMessageNotFound {
			c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
			return
		}
		h.logger.Error("failed to retry DLQ message", zap.String("id", id), zap.Error(err))
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to retry message"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"id":        event.ID,
		"topic":     event.Topic,
		"retried":   true,
		"timestamp": event.Timestamp,
	})
}
