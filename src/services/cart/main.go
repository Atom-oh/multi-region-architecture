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

// In-memory cart storage (used when Valkey is unavailable)
var memCartsMu sync.RWMutex
var memCarts = map[string]Cart{}

// OTel-instrumented HTTP client for inter-service calls
var serviceClient = tracing.HTTPClient()

// Lua script for atomic cart add — runs GET+modify+SET inside Redis without race conditions.
// KEYS[1] = cart key, ARGV[1] = item JSON, ARGV[2] = TTL seconds
const addItemScript = `
local cartJSON = redis.call('GET', KEYS[1])
local cart
if cartJSON then
  cart = cjson.decode(cartJSON)
else
  cart = {user_id=ARGV[3], items={}, total=0, item_count=0}
end
local newItem = cjson.decode(ARGV[1])
local found = false
for i, item in ipairs(cart.items) do
  if item.product_id == newItem.product_id then
    cart.items[i].quantity = item.quantity + newItem.quantity
    found = true
    break
  end
end
if not found then
  table.insert(cart.items, newItem)
end
local total = 0
local itemCount = 0
for _, item in ipairs(cart.items) do
  total = total + item.price * item.quantity
  itemCount = itemCount + item.quantity
end
cart.total = total
cart.item_count = itemCount
local updated = cjson.encode(cart)
redis.call('SET', KEYS[1], updated, 'EX', tonumber(ARGV[2]))
return updated
`

// Lua script for atomic cart remove — runs GET+modify+SET inside Redis without race conditions.
// KEYS[1] = cart key, ARGV[1] = product ID to remove, ARGV[2] = TTL seconds
const removeItemScript = `
local cartJSON = redis.call('GET', KEYS[1])
if not cartJSON then
  return nil
end
local cart = cjson.decode(cartJSON)
local newItems = {}
for _, item in ipairs(cart.items) do
  if item.product_id ~= ARGV[1] then
    table.insert(newItems, item)
  end
end
cart.items = newItems
local total = 0
local itemCount = 0
for _, item in ipairs(cart.items) do
  total = total + item.price * item.quantity
  itemCount = itemCount + item.quantity
end
cart.total = total
cart.item_count = itemCount
local updated = cjson.encode(cart)
redis.call('SET', KEYS[1], updated, 'EX', tonumber(ARGV[2]))
return updated
`

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
		var client *valkey.Client
		var err error
		if cfg.CacheWriteHost != "" {
			client, err = valkey.NewWithWriter(cfg.CacheHost, cfg.CacheWriteHost, cfg.CachePort, cfg.CachePassword)
		} else {
			client, err = valkey.New(cfg.CacheHost, cfg.CachePort, cfg.CachePassword)
		}
		if err != nil {
			log.Printf("WARNING: Valkey unavailable, using in-memory fallback: %v", err)
		} else {
			cacheClient = client
			defer cacheClient.Close()
			log.Printf("INFO: Connected to Valkey at %s:%d", cfg.CacheHost, cfg.CachePort)
		}
	} else {
		log.Printf("INFO: No CACHE_HOST configured, using in-memory fallback")
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

		// Fallback to in-memory data
		memCartsMu.RLock()
		cart, exists := memCarts[userID]
		memCartsMu.RUnlock()
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

		// Atomic add via Lua script — prevents race conditions on concurrent cart updates
		saved := false
		if cacheClient != nil {
			itemJSON, _ := json.Marshal(newItem)
			ttlSeconds := int(24 * time.Hour / time.Second)
			_, err := cacheClient.Eval(
				c.Request.Context(),
				addItemScript,
				[]string{"cart:" + userID},
				string(itemJSON),
				ttlSeconds,
				userID,
			)
			if err != nil {
				log.Printf("Valkey Lua addItem failed for user %s (falling back to in-memory): %v", userID, err)
			} else {
				saved = true
			}
		}

		// Fallback: save to in-memory map when Valkey is unavailable or write failed (e.g. READONLY replica)
		if !saved {
			memCartsMu.Lock()
			cart := memCarts[userID]
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
			memCarts[userID] = cart
			memCartsMu.Unlock()
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

		// Atomic remove via Lua script — prevents race conditions on concurrent cart updates
		removed := false
		if cacheClient != nil {
			ttlSeconds := int(24 * time.Hour / time.Second)
			_, err := cacheClient.Eval(
				c.Request.Context(),
				removeItemScript,
				[]string{"cart:" + userID},
				itemID,
				ttlSeconds,
			)
			if err != nil && err.Error() != "redis: nil" {
				log.Printf("Valkey Lua removeItem failed for user %s (falling back to in-memory): %v", userID, err)
			} else {
				removed = true
			}
		}

		// Fallback: remove from in-memory map
		if !removed {
			memCartsMu.Lock()
			if cart, exists := memCarts[userID]; exists {
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
				memCarts[userID] = cart
			}
			memCartsMu.Unlock()
		}

		c.JSON(http.StatusOK, gin.H{
			"message":    "상품이 장바구니에서 삭제되었습니다",
			"user_id":    userID,
			"item_id":    itemID,
			"removed_at": time.Now(),
		})
	}
}
