package main

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/kafka"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"go.uber.org/zap"
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

// Pre-defined topics for the shopping mall event bus
var availableTopics = []map[string]interface{}{
	{"name": "orders.created", "partitions": 6, "description": "Order creation events"},
	{"name": "orders.confirmed", "partitions": 6, "description": "Order confirmation events"},
	{"name": "orders.cancelled", "partitions": 3, "description": "Order cancellation events"},
	{"name": "payments.completed", "partitions": 6, "description": "Payment completion events"},
	{"name": "payments.failed", "partitions": 3, "description": "Payment failure events"},
	{"name": "catalog.updated", "partitions": 3, "description": "Product catalog update events"},
	{"name": "catalog.price-changed", "partitions": 3, "description": "Price change events"},
	{"name": "inventory.reserved", "partitions": 6, "description": "Inventory reservation events"},
	{"name": "inventory.released", "partitions": 6, "description": "Inventory release events"},
	{"name": "user.registered", "partitions": 3, "description": "User registration events"},
	{"name": "user.activity", "partitions": 6, "description": "User activity events"},
	{"name": "reviews.created", "partitions": 3, "description": "Review creation events"},
}

// Global Kafka producers - map of topic to producer (nil if Kafka unavailable)
var kafkaProducers = make(map[string]*kafka.Producer)
var kafkaAvailable = false
var logger *zap.Logger

func main() {
	cfg := config.Load("event-bus")

	// Initialize logger
	var err error
	logger, err = zap.NewProduction()
	if err != nil {
		log.Printf("WARNING: Failed to initialize zap logger: %v", err)
		logger, _ = zap.NewDevelopment()
	}
	defer logger.Sync()

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer func() { _ = tp.Shutdown(ctx) }()
	}

	// Initialize Kafka producers for all topics (graceful degradation if unavailable)
	initKafkaProducers(cfg)

	r := gin.Default()
	r.Use(tracing.GinMiddleware(cfg.ServiceName))
	r.Use(corsMiddleware())

	hc := health.New()
	hc.RegisterRoutes(r)

	// Root route for K8s probes
	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"service": cfg.ServiceName, "status": "ok", "kafka_available": kafkaAvailable})
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

func initKafkaProducers(cfg *config.Config) {
	if cfg.KafkaBrokers == "" || cfg.KafkaBrokers == "localhost:9092" {
		log.Printf("INFO: No MSK brokers configured (KAFKA_BROKERS=%s), using mock mode", cfg.KafkaBrokers)
		return
	}

	log.Printf("INFO: Initializing Kafka producers for MSK brokers: %s", cfg.KafkaBrokers)

	// Create a producer for each topic
	for _, topicInfo := range availableTopics {
		topicName := topicInfo["name"].(string)
		producer := kafka.NewProducer(cfg.KafkaBrokers, topicName, logger)
		kafkaProducers[topicName] = producer
	}

	kafkaAvailable = true
	log.Printf("INFO: Kafka producers initialized for %d topics", len(kafkaProducers))
}

func corsMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Requested-With")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

func publishEvent(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req PublishRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		event := Event{
			ID:        "evt_" + time.Now().Format("20060102150405"),
			Topic:     req.Topic,
			Key:       req.Key,
			Data:      req.Data,
			Timestamp: time.Now(),
		}

		// Publish to Kafka if available
		published := false
		if kafkaAvailable {
			producer, exists := kafkaProducers[req.Topic]
			if exists {
				// Wrap data with event metadata
				eventPayload := map[string]interface{}{
					"event_id":  event.ID,
					"topic":     event.Topic,
					"key":       event.Key,
					"data":      event.Data,
					"timestamp": event.Timestamp.Format(time.RFC3339),
				}
				if err := producer.Publish(c.Request.Context(), req.Key, eventPayload); err != nil {
					logger.Error("failed to publish to Kafka", zap.String("topic", req.Topic), zap.Error(err))
				} else {
					published = true
					logger.Debug("published event to Kafka", zap.String("topic", req.Topic), zap.String("key", req.Key))
				}
			} else {
				logger.Warn("no producer for topic", zap.String("topic", req.Topic))
			}
		}

		c.JSON(http.StatusAccepted, gin.H{
			"message":          "Event published successfully",
			"event":            event,
			"kafka_published":  published,
			"kafka_available":  kafkaAvailable,
		})
	}
}

func listTopics(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"topics":          availableTopics,
			"total_count":     len(availableTopics),
			"kafka_available": kafkaAvailable,
			"brokers":         cfg.KafkaBrokers,
		})
	}
}
