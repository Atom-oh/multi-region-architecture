package main

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

type Event struct {
	ID        string                 `json:"id"`
	Topic     string                 `json:"topic"`
	Key       string                 `json:"key"`
	Data      map[string]interface{} `json:"data"`
	Timestamp time.Time              `json:"timestamp"`
}

type PublishRequest struct {
	Topic string                 `json:"topic" binding:"required"`
	Key   string                 `json:"key" binding:"required"`
	Data  map[string]interface{} `json:"data" binding:"required"`
}

func main() {
	cfg := config.Load("event-bus")

	r := gin.Default()
	r.Use(tracing.GinMiddleware(cfg.ServiceName))

	hc := health.New()
	hc.RegisterRoutes(r)

	// Root route for K8s probes
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"service": cfg.ServiceName, "status": "ok"})
	})

	api := r.Group("/api/v1")
	{
		api.POST("/events", publishEvent(cfg))
		api.GET("/events/topics", listTopics(cfg))
	}

	hc.SetStarted(true)
	hc.SetReady(true)
	r.Run(":" + cfg.Port)
}

func publishEvent(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req PublishRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// Stub response - in production this would publish to Kafka
		event := Event{
			ID:        "evt_" + time.Now().Format("20060102150405"),
			Topic:     req.Topic,
			Key:       req.Key,
			Data:      req.Data,
			Timestamp: time.Now(),
		}

		c.JSON(http.StatusAccepted, gin.H{
			"message":       "event published",
			"event":         event,
			"kafka_brokers": cfg.KafkaBrokers,
			"stub_response": true,
		})
	}
}

func listTopics(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Stub response - in production this would list Kafka topics
		topics := []string{
			"orders.created",
			"orders.updated",
			"inventory.updated",
			"products.updated",
			"users.registered",
			"carts.updated",
			"payments.processed",
		}

		c.JSON(http.StatusOK, gin.H{
			"topics":        topics,
			"kafka_brokers": cfg.KafkaBrokers,
			"stub_response": true,
		})
	}
}
