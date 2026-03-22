package main

import (
	"context"
	"log"
	"math/rand"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/aurora"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

// Global DB client - nil if DB unavailable (graceful degradation)
var dbClient *aurora.Client

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

// Mock inventory data - consistent with shared product IDs
var mockInventory = map[string]InventoryItem{
	"PRD-001": {ProductID: "PRD-001", ProductName: "삼성 갤럭시 S25 울트라", SKU: "SAM-GS25U-256-BLK", Quantity: 150, Reserved: 23, Available: 127, Warehouse: "WH-SEOUL-001", Location: "서울 강남구"},
	"PRD-002": {ProductID: "PRD-002", ProductName: "나이키 에어맥스 97", SKU: "NIK-AM97-270-WHT", Quantity: 89, Reserved: 12, Available: 77, Warehouse: "WH-SEOUL-001", Location: "서울 강남구"},
	"PRD-003": {ProductID: "PRD-003", ProductName: "다이슨 에어랩", SKU: "DYS-AWC-COMP", Quantity: 45, Reserved: 8, Available: 37, Warehouse: "WH-BUSAN-001", Location: "부산 해운대구"},
	"PRD-004": {ProductID: "PRD-004", ProductName: "애플 맥북 프로 M4", SKU: "APL-MBP-M4-512", Quantity: 72, Reserved: 15, Available: 57, Warehouse: "WH-SEOUL-001", Location: "서울 강남구"},
	"PRD-005": {ProductID: "PRD-005", ProductName: "르크루제 냄비 세트", SKU: "LEC-POT-3SET-RED", Quantity: 120, Reserved: 5, Available: 115, Warehouse: "WH-BUSAN-001", Location: "부산 해운대구"},
	"PRD-006": {ProductID: "PRD-006", ProductName: "아디다스 울트라부스트", SKU: "ADI-UB23-280-BLK", Quantity: 200, Reserved: 30, Available: 170, Warehouse: "WH-SEOUL-001", Location: "서울 강남구"},
	"PRD-007": {ProductID: "PRD-007", ProductName: "LG 올레드 TV 65\"", SKU: "LG-OLED65-C4", Quantity: 35, Reserved: 7, Available: 28, Warehouse: "WH-SEOUL-002", Location: "서울 송파구"},
	"PRD-008": {ProductID: "PRD-008", ProductName: "무지 캔버스 토트백", SKU: "MUJ-CVS-TOTE-NAT", Quantity: 500, Reserved: 45, Available: 455, Warehouse: "WH-BUSAN-001", Location: "부산 해운대구"},
	"PRD-009": {ProductID: "PRD-009", ProductName: "스타벅스 텀블러 세트", SKU: "SBX-TMB-2SET-SS", Quantity: 300, Reserved: 22, Available: 278, Warehouse: "WH-SEOUL-001", Location: "서울 강남구"},
	"PRD-010": {ProductID: "PRD-010", ProductName: "소니 WH-1000XM5", SKU: "SNY-WH1000XM5-BLK", Quantity: 85, Reserved: 18, Available: 67, Warehouse: "WH-SEOUL-002", Location: "서울 송파구"},
}

// Low stock items
var lowStockItems = []InventoryItem{
	{ProductID: "PRD-007", ProductName: "LG 올레드 TV 65\"", SKU: "LG-OLED65-C4", Quantity: 8, Reserved: 5, Available: 3, Warehouse: "WH-BUSAN-001", Location: "부산 해운대구"},
	{ProductID: "PRD-003", ProductName: "다이슨 에어랩", SKU: "DYS-AWC-COMP", Quantity: 12, Reserved: 9, Available: 3, Warehouse: "WH-SEOUL-002", Location: "서울 송파구"},
	{ProductID: "PRD-004", ProductName: "애플 맥북 프로 M4", SKU: "APL-MBP-M4-1TB", Quantity: 15, Reserved: 10, Available: 5, Warehouse: "WH-BUSAN-001", Location: "부산 해운대구"},
}

func main() {
	cfg := config.Load("inventory")

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer func() { _ = tp.Shutdown(ctx) }()
	}

	// Initialize Aurora DB connection (graceful fallback to mock if unavailable)
	if cfg.DBHost != "" {
		client, err := aurora.New(ctx, cfg)
		if err != nil {
			log.Printf("WARNING: Aurora DB unavailable, using mock data: %v", err)
		} else {
			dbClient = client
			defer dbClient.Close()
			log.Printf("INFO: Connected to Aurora DB at %s:%d", cfg.DBHost, cfg.DBPort)
		}
	} else {
		log.Printf("INFO: No DB_HOST configured, using mock data")
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

func getInventory(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		productID := c.Param("productId")

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
				c.JSON(http.StatusOK, item)
				return
			}
			// Log DB error and fall through to mock data
			log.Printf("DB query failed for product %s: %v", productID, err)
		}

		// Fallback to mock data
		if item, exists := mockInventory[productID]; exists {
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

		// Fallback to mock data
		item, exists := mockInventory[productID]
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

		c.JSON(http.StatusOK, gin.H{
			"message":   "재고가 업데이트되었습니다",
			"operation": req.Operation,
			"reason":    req.Reason,
			"inventory": item,
		})
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

		// Fallback to mock data
		c.JSON(http.StatusOK, gin.H{
			"threshold": threshold,
			"count":     len(lowStockItems),
			"items":     lowStockItems,
			"message":   "재고 부족 상품 목록입니다. 빠른 보충이 필요합니다.",
		})
	}
}
