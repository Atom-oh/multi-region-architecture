package main

import (
	"context"
	"log"
	"math/rand"
	"net/http"
	"strconv"
	"time"

	"encoding/json"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/aurora"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/kafka"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
	"go.uber.org/zap"
)

// Global DB client - nil if DB unavailable (graceful degradation)
var dbClient *aurora.Client

// Global Valkey client - nil if unavailable (graceful degradation)
var cacheClient *valkey.Client

const inventoryCacheTTL = 30 * time.Second // Short TTL for inventory (frequently updated)

// Kafka producers for inventory events - nil if Kafka unavailable
var reservedProducer *kafka.Producer
var releasedProducer *kafka.Producer
var kafkaLogger *zap.Logger

type InventoryItem struct {
	ProductID   string    `json:"product_id"`
	ProductName string    `json:"product_name"`
	SKU         string    `json:"sku"`
	Quantity    int       `json:"quantity"`
	Reserved    int       `json:"reserved"`
	Available   int       `json:"available"`
	Warehouse   string    `json:"warehouse"`
	Location    string    `json:"location"`
	LastUpdated time.Time `json:"last_updated"`
}

type UpdateStockRequest struct {
	Quantity  int    `json:"quantity" binding:"required"`
	Operation string `json:"operation" binding:"required,oneof=set add subtract"`
	Reason    string `json:"reason"`
}

// In-memory inventory cache (used when Aurora DB is unavailable)
var memInventory = map[string]InventoryItem{}
var lowStockItems []InventoryItem

func main() {
	cfg := config.Load("inventory")

	// Initialize logger for Kafka
	var err error
	kafkaLogger, err = zap.NewProduction()
	if err != nil {
		log.Printf("WARNING: Failed to initialize zap logger: %v", err)
		kafkaLogger, _ = zap.NewDevelopment()
	}
	defer kafkaLogger.Sync()

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer func() { _ = tp.Shutdown(ctx) }()
	}

	// Initialize Valkey connection (graceful fallback if unavailable)
	if cfg.CacheHost != "" && cfg.CacheHost != "localhost" {
		var client *valkey.Client
		var err error
		if cfg.CacheWriteHost != "" {
			client, err = valkey.NewWithWriter(cfg.CacheHost, cfg.CacheWriteHost, cfg.CachePort, cfg.CachePassword)
		} else {
			client, err = valkey.New(cfg.CacheHost, cfg.CachePort, cfg.CachePassword)
		}
		if err != nil {
			log.Printf("WARNING: Valkey unavailable, inventory lookups will not be cached: %v", err)
		} else {
			cacheClient = client
			defer cacheClient.Close()
			log.Printf("INFO: Connected to Valkey at %s:%d", cfg.CacheHost, cfg.CachePort)
		}
	} else {
		log.Printf("INFO: No CACHE_HOST configured, inventory caching disabled")
	}

	// Initialize Aurora DB connection (graceful fallback to mock if unavailable)
	if cfg.DBHost != "" {
		client, err := aurora.New(ctx, cfg)
		if err != nil {
			log.Printf("WARNING: Aurora DB unavailable, using in-memory fallback: %v", err)
		} else {
			dbClient = client
			defer dbClient.Close()
			log.Printf("INFO: Connected to Aurora DB at %s:%d", cfg.DBHost, cfg.DBPort)
		}
	} else {
		log.Printf("INFO: No DB_HOST configured, using in-memory fallback")
	}

	// Initialize Kafka producers for inventory events (graceful degradation)
	if cfg.KafkaBrokers != "" && cfg.KafkaBrokers != "localhost:9092" {
		reservedProducer = kafka.NewProducer(cfg.KafkaBrokers, "inventory.reserved", kafkaLogger)
		releasedProducer = kafka.NewProducer(cfg.KafkaBrokers, "inventory.released", kafkaLogger)
		log.Printf("INFO: Kafka producers initialized for MSK brokers: %s", cfg.KafkaBrokers)
	} else {
		log.Printf("INFO: No MSK brokers configured (KAFKA_BROKERS=%s), Kafka events disabled", cfg.KafkaBrokers)
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
		api.GET("/inventory/:productId", getInventory(cfg))
		api.PUT("/inventory/:productId", updateStock(cfg))
		api.GET("/inventory/low-stock", getLowStock(cfg))
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

func inventoryCacheKey(productID string) string {
	return "inventory:" + productID
}

func getInventory(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		productID := c.Param("productId")

		// Try Valkey cache first
		if cacheClient != nil {
			cached, err := cacheClient.Get(c.Request.Context(), inventoryCacheKey(productID))
			if err == nil {
				var item InventoryItem
				if json.Unmarshal([]byte(cached), &item) == nil {
					c.JSON(http.StatusOK, item)
					return
				}
			}
		}

		// Try DB query first if available
		if dbClient != nil {
			var item InventoryItem
			err := dbClient.Pool.QueryRow(c.Request.Context(),
				`SELECT product_id, sku, quantity_available, quantity_reserved, warehouse_id, reorder_point, last_restocked_at, updated_at
				 FROM inventory WHERE product_id=$1`, productID).Scan(
				&item.ProductID, &item.SKU, &item.Quantity, &item.Reserved,
				&item.Warehouse, &item.Available, &item.Location, &item.LastUpdated)
			if err == nil {
				item.Available = item.Quantity - item.Reserved
				// Cache the DB result in Valkey
				if cacheClient != nil {
					data, _ := json.Marshal(item)
					_ = cacheClient.Set(c.Request.Context(), inventoryCacheKey(productID), data, inventoryCacheTTL)
				}
				c.JSON(http.StatusOK, item)
				return
			}
			// Log DB error and fall through to mock data
			log.Printf("DB query failed for product %s: %v", productID, err)
		}

		// Fallback to in-memory data
		if item, exists := memInventory[productID]; exists {
			item.LastUpdated = time.Now()
			c.JSON(http.StatusOK, item)
			return
		}

		// Return random stock for unknown products
		quantity := rand.Intn(490) + 10 // 10-500
		reserved := rand.Intn(quantity / 5)
		c.JSON(http.StatusOK, InventoryItem{
			ProductID:   productID,
			ProductName: "상품명 조회 중",
			SKU:         "SKU-" + productID,
			Quantity:    quantity,
			Reserved:    reserved,
			Available:   quantity - reserved,
			Warehouse:   "WH-SEOUL-001",
			Location:    "서울 강남구",
			LastUpdated: time.Now(),
		})
	}
}

func updateStock(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		productID := c.Param("productId")

		var req UpdateStockRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// Try DB update first if available
		if dbClient != nil {
			var updateSQL string
			switch req.Operation {
			case "set":
				updateSQL = `UPDATE inventory SET quantity_available = $2, updated_at = NOW() WHERE product_id = $1 RETURNING product_id, sku, quantity_available, quantity_reserved, warehouse_id, updated_at`
			case "add":
				updateSQL = `UPDATE inventory SET quantity_available = quantity_available + $2, updated_at = NOW() WHERE product_id = $1 RETURNING product_id, sku, quantity_available, quantity_reserved, warehouse_id, updated_at`
			case "subtract":
				updateSQL = `UPDATE inventory SET quantity_available = quantity_available - $2, updated_at = NOW() WHERE product_id = $1 RETURNING product_id, sku, quantity_available, quantity_reserved, warehouse_id, updated_at`
			}

			var item InventoryItem
			err := dbClient.Pool.QueryRow(c.Request.Context(), updateSQL, productID, req.Quantity).Scan(
				&item.ProductID, &item.SKU, &item.Quantity, &item.Reserved, &item.Warehouse, &item.LastUpdated)
			if err == nil {
				item.Available = item.Quantity - item.Reserved
				// Invalidate cache after update
				if cacheClient != nil {
					_ = cacheClient.Del(c.Request.Context(), inventoryCacheKey(productID))
				}
				c.JSON(http.StatusOK, gin.H{
					"message":   "재고가 업데이트되었습니다",
					"operation": req.Operation,
					"reason":    req.Reason,
					"inventory": item,
				})
				return
			}
			log.Printf("DB update failed for product %s: %v", productID, err)
		}

		// Fallback to in-memory data
		item, exists := memInventory[productID]
		if !exists {
			item = InventoryItem{
				ProductID: productID,
				SKU:       "SKU-" + productID,
				Quantity:  100,
				Reserved:  10,
				Available: 90,
				Warehouse: "WH-SEOUL-001",
				Location:  "서울 강남구",
			}
		}

		// Calculate new quantity based on operation
		newQuantity := req.Quantity
		switch req.Operation {
		case "add":
			newQuantity = item.Quantity + req.Quantity
		case "subtract":
			newQuantity = item.Quantity - req.Quantity
		}

		item.Quantity = newQuantity
		item.Available = newQuantity - item.Reserved
		item.LastUpdated = time.Now()

		// Publish inventory event to Kafka if available
		publishInventoryEvent(c.Request.Context(), productID, req.Operation, req.Quantity, req.Reason, item)

		c.JSON(http.StatusOK, gin.H{
			"message":   "재고가 업데이트되었습니다",
			"operation": req.Operation,
			"reason":    req.Reason,
			"inventory": item,
		})
	}
}

// publishInventoryEvent publishes inventory changes to Kafka
func publishInventoryEvent(ctx context.Context, productID, operation string, quantity int, reason string, item InventoryItem) {
	if reservedProducer == nil && releasedProducer == nil {
		return // Kafka not configured
	}

	event := map[string]interface{}{
		"event_type":  "inventory." + operation,
		"product_id":  productID,
		"operation":   operation,
		"quantity":    quantity,
		"reason":      reason,
		"new_total":   item.Quantity,
		"available":   item.Available,
		"reserved":    item.Reserved,
		"warehouse":   item.Warehouse,
		"timestamp":   time.Now().Format(time.RFC3339),
	}

	var producer *kafka.Producer
	if operation == "subtract" && reservedProducer != nil {
		producer = reservedProducer
	} else if operation == "add" && releasedProducer != nil {
		producer = releasedProducer
	}

	if producer != nil {
		if err := producer.Publish(ctx, productID, event); err != nil {
			kafkaLogger.Error("failed to publish inventory event",
				zap.String("product_id", productID),
				zap.String("operation", operation),
				zap.Error(err))
		} else {
			kafkaLogger.Debug("published inventory event",
				zap.String("product_id", productID),
				zap.String("operation", operation))
		}
	}
}

func getLowStock(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		thresholdStr := c.DefaultQuery("threshold", "20")
		threshold, _ := strconv.Atoi(thresholdStr)

		// Try DB query first if available
		if dbClient != nil {
			rows, err := dbClient.Pool.Query(c.Request.Context(),
				`SELECT product_id, sku, quantity_available, quantity_reserved, warehouse_id, reorder_point, updated_at
				 FROM inventory WHERE quantity_available < $1 ORDER BY quantity_available ASC`, threshold)
			if err == nil {
				defer rows.Close()
				var items []InventoryItem
				for rows.Next() {
					var item InventoryItem
					if err := rows.Scan(&item.ProductID, &item.SKU, &item.Quantity, &item.Reserved,
						&item.Warehouse, &item.Available, &item.LastUpdated); err == nil {
						item.Available = item.Quantity - item.Reserved
						items = append(items, item)
					}
				}
				if rows.Err() == nil {
					c.JSON(http.StatusOK, gin.H{
						"threshold": threshold,
						"count":     len(items),
						"items":     items,
						"message":   "재고 부족 상품 목록입니다. 빠른 보충이 필요합니다.",
					})
					return
				}
			}
			log.Printf("DB low stock query failed: %v", err)
		}

		// Fallback to in-memory data
		c.JSON(http.StatusOK, gin.H{
			"threshold": threshold,
			"count":     len(lowStockItems),
			"items":     lowStockItems,
			"message":   "재고 부족 상품 목록입니다. 빠른 보충이 필요합니다.",
		})
	}
}
