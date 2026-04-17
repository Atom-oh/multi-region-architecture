package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

type Product struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	Description string  `json:"description"`
	Price       int     `json:"price"`
	Category    string  `json:"category"`
	SellerID    string  `json:"seller_id"`
	SellerName  string  `json:"seller_name"`
	ImageURL    string  `json:"image_url"`
	Rating      float64 `json:"rating"`
	Score       float64 `json:"score"`
}

type SearchResponse struct {
	Query   string    `json:"query"`
	Total   int       `json:"total"`
	Results []Product `json:"results"`
	Took    string    `json:"took"`
}

type IndexRequest struct {
	ID          string   `json:"id" binding:"required"`
	Name        string   `json:"name" binding:"required"`
	Description string   `json:"description"`
	Price       int      `json:"price"`
	Category    string   `json:"category"`
	Tags        []string `json:"tags"`
}

// Global Valkey client - nil if unavailable (graceful degradation)
var cacheClient *valkey.Client

// Products are fetched from product-catalog service at runtime
var emptyProducts []Product

// OTel-instrumented HTTP client for inter-service calls
var serviceClient = tracing.HTTPClient()

const (
	catalogCacheKey = "search:catalog:all"
	catalogCacheTTL = 5 * time.Minute // Cache product catalog for 5 minutes
	searchCacheTTL  = 2 * time.Minute // Cache search results for 2 minutes
)

func main() {
	cfg := config.Load("search")

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer tp.Shutdown(ctx)
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
			log.Printf("WARNING: Valkey unavailable, search results will not be cached: %v", err)
		} else {
			cacheClient = client
			defer cacheClient.Close()
			log.Printf("INFO: Connected to Valkey at %s:%d", cfg.CacheHost, cfg.CachePort)
		}
	} else {
		log.Printf("INFO: No CACHE_HOST configured, search caching disabled")
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
		api.GET("/search", searchProducts(cfg))
		api.POST("/search/index", indexProduct(cfg))
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

// fetchCatalogProducts fetches product catalog with Valkey cache-aside pattern.
func fetchCatalogProducts(ctx context.Context) []Product {
	// Try Valkey cache first
	if cacheClient != nil {
		cached, err := cacheClient.Get(ctx, catalogCacheKey)
		if err == nil {
			var products []Product
			if json.Unmarshal([]byte(cached), &products) == nil && len(products) > 0 {
				return products
			}
		}
	}

	// Cache miss or unavailable — fetch from product-catalog service
	catalogURL := "http://product-catalog.core-services.svc.cluster.local:80/api/v1/products"
	httpReq, err := http.NewRequestWithContext(ctx, "GET", catalogURL, nil)
	if err != nil {
		return emptyProducts
	}
	resp, err := serviceClient.Do(httpReq)
	if err != nil {
		return emptyProducts
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return emptyProducts
	}

	var catalog struct {
		Products []Product `json:"products"`
	}
	if json.NewDecoder(resp.Body).Decode(&catalog) != nil || len(catalog.Products) == 0 {
		return emptyProducts
	}

	// Store in Valkey cache
	if cacheClient != nil {
		data, err := json.Marshal(catalog.Products)
		if err == nil {
			if err := cacheClient.Set(ctx, catalogCacheKey, data, catalogCacheTTL); err != nil {
				log.Printf("WARNING: Failed to cache catalog products: %v", err)
			}
		}
	}

	return catalog.Products
}

func searchProducts(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		query := c.Query("q")
		if query == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "검색어를 입력해주세요 (query parameter 'q' is required)"})
			return
		}

		start := time.Now()
		queryLower := strings.ToLower(query)

		// Try search result cache first
		searchResultCacheKey := "search:result:" + queryLower
		if cacheClient != nil {
			cached, err := cacheClient.Get(c.Request.Context(), searchResultCacheKey)
			if err == nil {
				var response SearchResponse
				if json.Unmarshal([]byte(cached), &response) == nil {
					response.Took = time.Since(start).String()
					c.JSON(http.StatusOK, response)
					return
				}
			}
		}

		// Cache miss — fetch catalog (also cached) and filter
		searchSource := fetchCatalogProducts(c.Request.Context())

		// Filter products that match the query
		var results []Product
		for _, p := range searchSource {
			nameLower := strings.ToLower(p.Name)
			descLower := strings.ToLower(p.Description)
			catLower := strings.ToLower(p.Category)

			if strings.Contains(nameLower, queryLower) ||
				strings.Contains(descLower, queryLower) ||
				strings.Contains(catLower, queryLower) {
				results = append(results, p)
			}
		}

		// If no results, return all products as suggestions
		if len(results) == 0 {
			results = searchSource
		}

		response := SearchResponse{
			Query:   query,
			Total:   len(results),
			Results: results,
			Took:    time.Since(start).String(),
		}

		// Cache search results
		if cacheClient != nil {
			data, _ := json.Marshal(response)
			if err := cacheClient.Set(c.Request.Context(), searchResultCacheKey, data, searchCacheTTL); err != nil {
				log.Printf("WARNING: Failed to cache search results: %v", err)
			}
		}

		c.JSON(http.StatusOK, response)
	}
}

func indexProduct(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req IndexRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// Invalidate catalog and search result caches so new/updated products appear immediately
		if cacheClient != nil {
			ctx := c.Request.Context()
			if err := cacheClient.Del(ctx, catalogCacheKey); err != nil {
				log.Printf("WARN: failed to invalidate catalog cache: %v", err)
			}
			if err := cacheClient.DelPattern(ctx, "search:result:*"); err != nil {
				log.Printf("WARN: failed to invalidate search result cache: %v", err)
			}
		}

		c.JSON(http.StatusCreated, gin.H{
			"message":    "상품이 검색 인덱스에 추가되었습니다",
			"product_id": req.ID,
			"index":      "products",
			"indexed_at": time.Now(),
		})
	}
}
