package main

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

type SearchResult struct {
	ID          string   `json:"id"`
	Name        string   `json:"name"`
	Description string   `json:"description"`
	Price       float64  `json:"price"`
	Category    string   `json:"category"`
	Tags        []string `json:"tags"`
	Score       float64  `json:"score"`
}

type SearchResponse struct {
	Query   string         `json:"query"`
	Total   int            `json:"total"`
	Results []SearchResult `json:"results"`
	Took    string         `json:"took"`
}

type IndexRequest struct {
	ID          string   `json:"id" binding:"required"`
	Name        string   `json:"name" binding:"required"`
	Description string   `json:"description"`
	Price       float64  `json:"price"`
	Category    string   `json:"category"`
	Tags        []string `json:"tags"`
}

func main() {
	cfg := config.Load("search")

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
		api.GET("/search", searchProducts(cfg))
		api.POST("/search/index", indexProduct(cfg))
	}

	hc.SetStarted(true)
	hc.SetReady(true)
	r.Run(":" + cfg.Port)
}

func searchProducts(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		query := c.Query("q")
		if query == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "query parameter 'q' is required"})
			return
		}

		start := time.Now()

		// Stub response - in production this would query OpenSearch
		results := []SearchResult{
			{
				ID:          "prod_001",
				Name:        "Sample Product matching: " + query,
				Description: "A great product that matches your search",
				Price:       29.99,
				Category:    "Electronics",
				Tags:        []string{"popular", "sale"},
				Score:       0.95,
			},
			{
				ID:          "prod_002",
				Name:        "Another Product for: " + query,
				Description: "Another excellent product",
				Price:       49.99,
				Category:    "Home & Garden",
				Tags:        []string{"new"},
				Score:       0.87,
			},
		}

		response := SearchResponse{
			Query:   query,
			Total:   len(results),
			Results: results,
			Took:    time.Since(start).String(),
		}

		c.JSON(http.StatusOK, gin.H{
			"response":        response,
			"opensearch_url":  cfg.OpenSearchURL,
			"stub_response":   true,
		})
	}
}

func indexProduct(cfg *config.Config) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req IndexRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		// Stub response - in production this would index to OpenSearch
		c.JSON(http.StatusCreated, gin.H{
			"message":        "product indexed",
			"product_id":     req.ID,
			"index":          "products",
			"opensearch_url": cfg.OpenSearchURL,
			"stub_response":  true,
		})
	}
}
