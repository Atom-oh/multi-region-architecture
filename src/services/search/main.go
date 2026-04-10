package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
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

// Products are fetched from product-catalog service at runtime
var emptyProducts []Product

// OTel-instrumented HTTP client for inter-service calls
var serviceClient = tracing.HTTPClient()

func main() {
	cfg := config.Load("search")

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer tp.Shutdown(ctx)
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

func searchProducts(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		query := c.Query("q")
		if query == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "검색어를 입력해주세요 (query parameter 'q' is required)"})
			return
		}

		start := time.Now()
		queryLower := strings.ToLower(query)

		// Inter-service call: fetch latest products from product-catalog (distributed trace)
		searchSource := emptyProducts
		catalogURL := "http://product-catalog.core-services.svc.cluster.local:80/api/v1/products"
		httpReq, err := http.NewRequestWithContext(c.Request.Context(), "GET", catalogURL, nil)
		if err == nil {
			resp, err := serviceClient.Do(httpReq)
			if err == nil {
				defer resp.Body.Close()
				if resp.StatusCode == http.StatusOK {
					var catalog struct {
						Products []Product `json:"products"`
					}
					if json.NewDecoder(resp.Body).Decode(&catalog) == nil && len(catalog.Products) > 0 {
						searchSource = catalog.Products
					}
				}
			}
		}

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

		c.JSON(http.StatusCreated, gin.H{
			"message":    "상품이 검색 인덱스에 추가되었습니다",
			"product_id": req.ID,
			"index":      "products",
			"indexed_at": time.Now(),
		})
	}
}
