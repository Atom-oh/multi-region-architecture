package main

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

type CartItem struct {
	ProductID string  `json:"product_id"`
	Name      string  `json:"name"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

type Cart struct {
	UserID    string     `json:"user_id"`
	Items     []CartItem `json:"items"`
	Total     float64    `json:"total"`
	UpdatedAt time.Time  `json:"updated_at"`
}

type AddItemRequest struct {
	ProductID string  `json:"product_id" binding:"required"`
	Name      string  `json:"name" binding:"required"`
	Quantity  int     `json:"quantity" binding:"required,min=1"`
	Price     float64 `json:"price" binding:"required,min=0"`
}

func main() {
	cfg := config.Load("cart")

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
		api.GET("/carts/:userId", getCart(cfg))
		api.POST("/carts/:userId", addItem(cfg))
		api.DELETE("/carts/:userId", removeItem(cfg))
	}

	hc.SetStarted(true)
	hc.SetReady(true)
	r.Run(":" + cfg.Port)
}

func getCart(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		// Stub response - in production this would fetch from Valkey/Redis
		cart := Cart{
			UserID: userID,
			Items: []CartItem{
				{ProductID: "prod_001", Name: "Sample Product", Quantity: 2, Price: 29.99},
			},
			Total:     59.98,
			UpdatedAt: time.Now(),
		}

		c.JSON(http.StatusOK, gin.H{
			"cart":          cart,
			"cache_host":    cfg.CacheHost,
			"stub_response": true,
		})
	}
}

func addItem(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		var req AddItemRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// Stub response - in production this would add to Valkey/Redis
		cart := Cart{
			UserID: userID,
			Items: []CartItem{
				{ProductID: req.ProductID, Name: req.Name, Quantity: req.Quantity, Price: req.Price},
			},
			Total:     req.Price * float64(req.Quantity),
			UpdatedAt: time.Now(),
		}

		c.JSON(http.StatusOK, gin.H{
			"message":       "item added to cart",
			"cart":          cart,
			"stub_response": true,
		})
	}
}

func removeItem(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")
		productID := c.Query("product_id")

		if productID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "product_id query parameter required"})
			return
		}

		// Stub response - in production this would remove from Valkey/Redis
		c.JSON(http.StatusOK, gin.H{
			"message":       "item removed from cart",
			"user_id":       userID,
			"product_id":    productID,
			"stub_response": true,
		})
	}
}
