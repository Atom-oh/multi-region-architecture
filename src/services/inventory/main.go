package main

import (
	"math/rand"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

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

		c.JSON(http.StatusOK, gin.H{
			"threshold": threshold,
			"count":     len(lowStockItems),
			"items":     lowStockItems,
			"message":   "재고 부족 상품 목록입니다. 빠른 보충이 필요합니다.",
		})
	}
}
