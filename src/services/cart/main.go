package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

// Global Valkey client - nil if unavailable (graceful degradation)
var cacheClient *valkey.Client

type CartItem struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
	Quantity  int    `json:"quantity"`
	Price     int    `json:"price"`
	ImageURL  string `json:"image_url"`
}

type Cart struct {
	UserID    string     `json:"user_id"`
	Items     []CartItem `json:"items"`
	Total     int        `json:"total"`
	ItemCount int        `json:"item_count"`
	UpdatedAt time.Time  `json:"updated_at"`
}

type AddItemRequest struct {
	ProductID string `json:"product_id" binding:"required"`
	Name      string `json:"name" binding:"required"`
	Quantity  int    `json:"quantity" binding:"required,min=1"`
	Price     int    `json:"price" binding:"required,min=0"`
}

// Cart data stored in Valkey (Redis) at runtime
var mockCartsMu sync.RWMutex
var mockCarts = map[string]Cart{}

// OTel-instrumented HTTP client for inter-service calls
var serviceClient = tracing.HTTPClient()

func main() {
	cfg := config.Load("cart")

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer tp.Shutdown(ctx)
	}

	// Initialize Valkey connection (graceful fallback to mock if unavailable)
	if cfg.CacheHost != "" {
		client, err := valkey.New(cfg.CacheHost, cfg.CachePort, cfg.CachePassword)
		if err != nil {
			log.Printf("WARNING: Valkey unavailable, using mock data: %v", err)
		} else {
			cacheClient = client
			defer cacheClient.Close()
			log.Printf("INFO: Connected to Valkey at %s:%d", cfg.CacheHost, cfg.CachePort)
		}
	} else {
		log.Printf("INFO: No CACHE_HOST configured, using mock data")
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
		api.GET("/carts/:userId", getCart(cfg))
		api.POST("/carts/:userId", addItem(cfg))
		api.DELETE("/carts/:userId/items/:itemId", removeItem(cfg))
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

func getCart(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		// Try Valkey first if available
		if cacheClient != nil {
			cartJSON, err := cacheClient.Get(c.Request.Context(), "cart:"+userID)
			if err == nil {
				var cart Cart
				if json.Unmarshal([]byte(cartJSON), &cart) == nil {
					cart.UpdatedAt = time.Now()
					c.JSON(http.StatusOK, cart)
					return
				}
			}
			// Key not found is not an error, fall through to mock/empty
			if err != nil && err.Error() != "redis: nil" {
				log.Printf("Valkey get failed for user %s: %v", userID, err)
			}
		}

		// Fallback to mock data
		mockCartsMu.RLock()
		cart, exists := mockCarts[userID]
		mockCartsMu.RUnlock()
		if exists {
			cart.UpdatedAt = time.Now()
			c.JSON(http.StatusOK, cart)
			return
		}

		// Return empty cart for unknown users
		c.JSON(http.StatusOK, Cart{
			UserID:    userID,
			Items:     []CartItem{},
			Total:     0,
			ItemCount: 0,
			UpdatedAt: time.Now(),
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

		// Inter-service call: fetch product details from product-catalog (distributed trace)
		productName := req.Name
		productPrice := req.Price
		productImage := "https://placehold.co/400x400/EEE/333?text=Product"

		catalogURL := fmt.Sprintf("http://product-catalog.core-services.svc.cluster.local:80/api/v1/products/%s", req.ProductID)
		httpReq, err := http.NewRequestWithContext(c.Request.Context(), "GET", catalogURL, nil)
		if err == nil {
			resp, err := serviceClient.Do(httpReq)
			if err == nil {
				defer resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					var product map[string]interface{}
					if json.NewDecoder(resp.Body).Decode(&product) == nil {
						if name, ok := product["name"].(string); ok && name != "" {
							productName = name
						}
						if price, ok := product["price"].(float64); ok && price > 0 {
							productPrice = int(price)
						}
						if img, ok := product["image_url"].(string); ok && img != "" {
							productImage = img
						}
					}
				}
			}
		}

		newItem := CartItem{
			ProductID: req.ProductID,
			Name:      productName,
			Quantity:  req.Quantity,
			Price:     productPrice,
			ImageURL:  productImage,
		}

		// Get current cart, add item, and save to Valkey (fallback to in-memory)
		saved := false
		if cacheClient != nil {
			var cart Cart
			cartJSON, err := cacheClient.Get(c.Request.Context(), "cart:"+userID)
			if err == nil {
				_ = json.Unmarshal([]byte(cartJSON), &cart)
			}
			if cart.UserID == "" {
				cart = Cart{UserID: userID, Items: []CartItem{}}
			}

			// Check if item already exists, update quantity if so
			found := false
			for i, item := range cart.Items {
				if item.ProductID == req.ProductID {
					cart.Items[i].Quantity += req.Quantity
					found = true
					break
				}
			}
			if !found {
				cart.Items = append(cart.Items, newItem)
			}

			// Recalculate totals
			cart.Total = 0
			cart.ItemCount = 0
			for _, item := range cart.Items {
				cart.Total += item.Price * item.Quantity
				cart.ItemCount += item.Quantity
			}
			cart.UpdatedAt = time.Now()

			// Save to Valkey with 24h TTL
			updatedCartJSON, _ := json.Marshal(cart)
			if err := cacheClient.Set(c.Request.Context(), "cart:"+userID, updatedCartJSON, 24*time.Hour); err != nil {
				log.Printf("Valkey set failed for user %s (falling back to in-memory): %v", userID, err)
			} else {
				saved = true
			}
		}

		// Fallback: save to in-memory map when Valkey is unavailable or write failed (e.g. READONLY replica)
		if !saved {
			mockCartsMu.Lock()
			cart := mockCarts[userID]
			if cart.UserID == "" {
				cart = Cart{UserID: userID, Items: []CartItem{}}
			}
			found := false
			for i, item := range cart.Items {
				if item.ProductID == req.ProductID {
					cart.Items[i].Quantity += req.Quantity
					found = true
					break
				}
			}
			if !found {
				cart.Items = append(cart.Items, newItem)
			}
			cart.Total = 0
			cart.ItemCount = 0
			for _, item := range cart.Items {
				cart.Total += item.Price * item.Quantity
				cart.ItemCount += item.Quantity
			}
			cart.UpdatedAt = time.Now()
			mockCarts[userID] = cart
			mockCartsMu.Unlock()
			log.Printf("INFO: Cart saved to in-memory fallback for user %s", userID)
		}

		c.JSON(http.StatusOK, gin.H{
			"message":    "상품이 장바구니에 추가되었습니다",
			"user_id":    userID,
			"item":       newItem,
			"updated_at": time.Now(),
		})
	}
}

func removeItem(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")
		itemID := c.Param("itemId") // itemID is the productID to remove

		// Remove from Valkey if available, fallback to in-memory
		removed := false
		if cacheClient != nil {
			cartJSON, err := cacheClient.Get(c.Request.Context(), "cart:"+userID)
			if err == nil {
				var cart Cart
				if json.Unmarshal([]byte(cartJSON), &cart) == nil {
					newItems := []CartItem{}
					for _, item := range cart.Items {
						if item.ProductID != itemID {
							newItems = append(newItems, item)
						}
					}
					cart.Items = newItems

					cart.Total = 0
					cart.ItemCount = 0
					for _, item := range cart.Items {
						cart.Total += item.Price * item.Quantity
						cart.ItemCount += item.Quantity
					}
					cart.UpdatedAt = time.Now()

					updatedCartJSON, _ := json.Marshal(cart)
					if err := cacheClient.Set(c.Request.Context(), "cart:"+userID, updatedCartJSON, 24*time.Hour); err != nil {
						log.Printf("Valkey set failed for user %s (falling back to in-memory): %v", userID, err)
					} else {
						removed = true
					}
				}
			}
		}

		// Fallback: remove from in-memory map
		if !removed {
			mockCartsMu.Lock()
			if cart, exists := mockCarts[userID]; exists {
				newItems := []CartItem{}
				for _, item := range cart.Items {
					if item.ProductID != itemID {
						newItems = append(newItems, item)
					}
				}
				cart.Items = newItems
				cart.Total = 0
				cart.ItemCount = 0
				for _, item := range cart.Items {
					cart.Total += item.Price * item.Quantity
					cart.ItemCount += item.Quantity
				}
				cart.UpdatedAt = time.Now()
				mockCarts[userID] = cart
			}
			mockCartsMu.Unlock()
		}

		c.JSON(http.StatusOK, gin.H{
			"message":    "상품이 장바구니에서 삭제되었습니다",
			"user_id":    userID,
			"item_id":    itemID,
			"removed_at": time.Now(),
		})
	}
}
