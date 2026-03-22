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

// Mock product data - consistent with shared IDs
var mockProducts = []Product{
	{ID: "PRD-001", Name: "삼성 갤럭시 S25 울트라", Description: "최신 플래그십 스마트폰, AI 카메라 탑재", Price: 1890000, Category: "electronics", SellerID: "SEL-001", SellerName: "삼성전자 Official", ImageURL: "https://placehold.co/400x400/EEE/333?text=Galaxy+S25", Rating: 4.8, Score: 0.98},
	{ID: "PRD-002", Name: "나이키 에어맥스 97", Description: "클래식한 디자인의 러닝화", Price: 189000, Category: "shoes", SellerID: "SEL-002", SellerName: "Nike Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=AirMax+97", Rating: 4.6, Score: 0.95},
	{ID: "PRD-003", Name: "다이슨 에어랩", Description: "멀티 스타일러 헤어 드라이기", Price: 699000, Category: "beauty", SellerID: "SEL-003", SellerName: "Dyson Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap", Rating: 4.9, Score: 0.97},
	{ID: "PRD-004", Name: "애플 맥북 프로 M4", Description: "M4 칩 탑재 프로페셔널 노트북", Price: 2990000, Category: "electronics", SellerID: "SEL-004", SellerName: "Apple Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=MacBook+M4", Rating: 4.9, Score: 0.96},
	{ID: "PRD-005", Name: "르크루제 냄비 세트", Description: "프리미엄 주철 냄비 3종 세트", Price: 459000, Category: "kitchen", SellerID: "SEL-005", SellerName: "Le Creuset Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=Le+Creuset", Rating: 4.7, Score: 0.92},
	{ID: "PRD-006", Name: "아디다스 울트라부스트", Description: "편안한 쿠셔닝의 러닝화", Price: 219000, Category: "shoes", SellerID: "SEL-006", SellerName: "Adidas Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=Ultraboost", Rating: 4.5, Score: 0.91},
	{ID: "PRD-007", Name: "LG 올레드 TV 65\"", Description: "65인치 4K OLED 스마트 TV", Price: 3290000, Category: "electronics", SellerID: "SEL-007", SellerName: "LG전자 Official", ImageURL: "https://placehold.co/400x400/EEE/333?text=LG+OLED+65", Rating: 4.8, Score: 0.94},
	{ID: "PRD-008", Name: "무지 캔버스 토트백", Description: "심플한 디자인의 캔버스 가방", Price: 29000, Category: "fashion", SellerID: "SEL-008", SellerName: "MUJI Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=MUJI+Tote", Rating: 4.3, Score: 0.88},
	{ID: "PRD-009", Name: "스타벅스 텀블러 세트", Description: "스테인리스 텀블러 2종 세트", Price: 45000, Category: "kitchen", SellerID: "SEL-009", SellerName: "Starbucks Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=Starbucks", Rating: 4.4, Score: 0.87},
	{ID: "PRD-010", Name: "소니 WH-1000XM5", Description: "프리미엄 노이즈캔슬링 헤드폰", Price: 429000, Category: "electronics", SellerID: "SEL-010", SellerName: "Sony Korea", ImageURL: "https://placehold.co/400x400/EEE/333?text=Sony+XM5", Rating: 4.8, Score: 0.96},
}

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
		searchSource := mockProducts
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
