package main

import (
	"context"
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

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer func() { _ = tp.Shutdown(ctx) }()
	}

	r := gin.Default()
	r.Use(tracing.GinMiddleware(cfg.ServiceName))
	r.Use(corsMiddleware())

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

		c.JSON(http.StatusAccepted, gin.H{
			"message": "이벤트가 발행되었습니다",
			"event":   event,
		})
	}
}

func listTopics(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		topics := []map[string]interface{}{
			{"name": "orders.created", "partitions": 6, "description": "주문 생성 이벤트"},
			{"name": "orders.updated", "partitions": 6, "description": "주문 상태 변경 이벤트"},
			{"name": "orders.cancelled", "partitions": 3, "description": "주문 취소 이벤트"},
			{"name": "inventory.updated", "partitions": 6, "description": "재고 변경 이벤트"},
			{"name": "inventory.low-stock", "partitions": 3, "description": "재고 부족 알림 이벤트"},
			{"name": "products.created", "partitions": 3, "description": "상품 등록 이벤트"},
			{"name": "products.updated", "partitions": 3, "description": "상품 정보 변경 이벤트"},
			{"name": "users.registered", "partitions": 3, "description": "회원 가입 이벤트"},
			{"name": "users.profile-updated", "partitions": 3, "description": "회원 정보 변경 이벤트"},
			{"name": "carts.updated", "partitions": 6, "description": "장바구니 변경 이벤트"},
			{"name": "payments.processed", "partitions": 6, "description": "결제 완료 이벤트"},
			{"name": "payments.refunded", "partitions": 3, "description": "환불 처리 이벤트"},
			{"name": "shipments.created", "partitions": 6, "description": "배송 생성 이벤트"},
			{"name": "shipments.status-changed", "partitions": 6, "description": "배송 상태 변경 이벤트"},
			{"name": "notifications.send", "partitions": 6, "description": "알림 발송 이벤트"},
		}

		c.JSON(http.StatusOK, gin.H{
			"topics":      topics,
			"total_count": len(topics),
		})
	}
}
