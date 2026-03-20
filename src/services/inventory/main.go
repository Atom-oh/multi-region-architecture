package main

import (
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
	SKU         string    `json:"sku"`
	Quantity    int       `json:"quantity"`
	Reserved    int       `json:"reserved"`
	Available   int       `json:"available"`
	Warehouse   string    `json:"warehouse"`
	LastUpdated time.Time `json:"last_updated"`
}

type UpdateStockRequest struct {
	Quantity  int    `json:"quantity" binding:"required"`
	Operation string `json:"operation" binding:"required,oneof=set add subtract"`
	Reason    string `json:"reason"`
}

func main() {
	cfg := config.Load("inventory")

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
		api.GET("/inventory/:productId", getInventory(cfg))
		api.PUT("/inventory/:productId", updateStock(cfg))
		api.GET("/inventory/low-stock", getLowStock(cfg))
	}

	hc.SetStarted(true)
	hc.SetReady(true)
	r.Run(":" + cfg.Port)
}

func getInventory(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		productID := c.Param("productId")

		// Stub response - in production this would query Aurora PostgreSQL
		item := InventoryItem{
			ProductID:   productID,
			SKU:         "SKU-" + productID,
			Quantity:    100,
			Reserved:    10,
			Available:   90,
			Warehouse:   cfg.AWSRegion + "-warehouse-1",
			LastUpdated: time.Now(),
		}

		c.JSON(http.StatusOK, gin.H{
			"inventory":     item,
			"db_host":       cfg.DBHost,
			"stub_response": true,
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

		// Stub response - in production this would update Aurora PostgreSQL
		newQuantity := req.Quantity
		if req.Operation == "add" {
			newQuantity = 100 + req.Quantity
		} else if req.Operation == "subtract" {
			newQuantity = 100 - req.Quantity
		}

		item := InventoryItem{
			ProductID:   productID,
			SKU:         "SKU-" + productID,
			Quantity:    newQuantity,
			Reserved:    10,
			Available:   newQuantity - 10,
			Warehouse:   cfg.AWSRegion + "-warehouse-1",
			LastUpdated: time.Now(),
		}

		c.JSON(http.StatusOK, gin.H{
			"message":       "stock updated",
			"operation":     req.Operation,
			"inventory":     item,
			"stub_response": true,
		})
	}
}

func getLowStock(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		thresholdStr := c.DefaultQuery("threshold", "10")
		threshold, _ := strconv.Atoi(thresholdStr)

		// Stub response - in production this would query Aurora PostgreSQL
		lowStockItems := []InventoryItem{
			{
				ProductID:   "prod_low_001",
				SKU:         "SKU-LOW-001",
				Quantity:    5,
				Reserved:    2,
				Available:   3,
				Warehouse:   cfg.AWSRegion + "-warehouse-1",
				LastUpdated: time.Now(),
			},
			{
				ProductID:   "prod_low_002",
				SKU:         "SKU-LOW-002",
				Quantity:    8,
				Reserved:    1,
				Available:   7,
				Warehouse:   cfg.AWSRegion + "-warehouse-2",
				LastUpdated: time.Now(),
			},
		}

		c.JSON(http.StatusOK, gin.H{
			"threshold":     threshold,
			"count":         len(lowStockItems),
			"items":         lowStockItems,
			"db_host":       cfg.DBHost,
			"stub_response": true,
		})
	}
}
