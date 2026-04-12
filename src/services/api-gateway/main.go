package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/auth"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

var tracedClient = tracing.HTTPClient()

// Global Valkey client for rate limiting - nil if unavailable
var cacheClient *valkey.Client

const (
	rateLimitWindow   = 60 * time.Second // 1-minute sliding window
	rateLimitMaxReqs  = 100              // Max 100 requests per minute per IP
	rateLimitCacheTTL = 70 * time.Second // Slightly longer than window for cleanup
)

func main() {
	cfg := config.Load("api-gateway")

	// Initialize OTel tracer — exports spans to OTel Collector
	ctx := context.Background()
	tp, err := tracing.InitTracer(ctx, cfg.ServiceName)
	if err == nil {
		defer func() { _ = tp.Shutdown(ctx) }()
	}

	// Initialize Valkey connection for rate limiting (graceful fallback)
	if cfg.CacheHost != "" && cfg.CacheHost != "localhost" {
		client, err := valkey.New(cfg.CacheHost, cfg.CachePort, cfg.CachePassword)
		if err != nil {
			log.Printf("WARNING: Valkey unavailable, rate limiting disabled: %v", err)
		} else {
			cacheClient = client
			defer cacheClient.Close()
			log.Printf("INFO: Connected to Valkey at %s:%d (rate limiting enabled)", cfg.CacheHost, cfg.CachePort)
		}
	} else {
		log.Printf("INFO: No CACHE_HOST configured, rate limiting disabled")
	}

	// Load auth configuration from environment variables
	// If COGNITO_USER_POOL_ID is not set, auth is skipped (graceful degradation)
	authCfg := auth.LoadConfigFromEnv()

	r := gin.Default()
	r.Use(tracing.GinMiddleware(cfg.ServiceName))
	r.Use(corsMiddleware())
	r.Use(rateLimitMiddleware())

	hc := health.New()
	hc.RegisterRoutes(r)

	// Root route - returns mall landing page HTML (public)
	r.GET("/", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(mallLandingHTML))
	})

	// API health endpoint (public)
	r.GET("/api/v1/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": cfg.ServiceName,
			"region":  cfg.AWSRegion,
			"version": "1.0.0",
			"uptime":  "99.99%",
		})
	})

	// Public routes - no authentication required
	publicAPI := r.Group("/api/v1")
	{
		// Auth endpoints (login/register) - must be public
		publicAPI.Any("/users/login", reverseProxy("user-account.user-services.svc.cluster.local:80"))
		publicAPI.Any("/users/register", reverseProxy("user-account.user-services.svc.cluster.local:80"))

		// Product catalog - public for browsing
		publicAPI.GET("/products", reverseProxy("product-catalog.core-services.svc.cluster.local:80"))
		publicAPI.GET("/products/*path", reverseProxy("product-catalog.core-services.svc.cluster.local:80"))

		// Search - public for product discovery
		publicAPI.GET("/search/*path", reverseProxy("search.core-services.svc.cluster.local:80"))

		// Reviews - public for reading (writing requires auth)
		publicAPI.GET("/reviews", reverseProxy("review.user-services.svc.cluster.local:80"))
		publicAPI.GET("/reviews/*path", reverseProxy("review.user-services.svc.cluster.local:80"))

		// Recommendations - public for product suggestions
		publicAPI.GET("/recommendations/*path", reverseProxy("recommendation.business-services.svc.cluster.local:80"))

		// Prices - public for viewing prices
		publicAPI.GET("/prices/*path", reverseProxy("pricing.business-services.svc.cluster.local:80"))
	}

	// Protected routes - authentication required
	protectedAPI := r.Group("/api/v1")
	protectedAPI.Use(auth.Middleware(authCfg))
	{
		// Product management (POST/PUT/DELETE)
		protectedAPI.POST("/products/*path", reverseProxy("product-catalog.core-services.svc.cluster.local:80"))
		protectedAPI.PUT("/products/*path", reverseProxy("product-catalog.core-services.svc.cluster.local:80"))
		protectedAPI.DELETE("/products/*path", reverseProxy("product-catalog.core-services.svc.cluster.local:80"))

		// Inventory management
		protectedAPI.Any("/inventory/*path", reverseProxy("inventory.core-services.svc.cluster.local:80"))

		// Cart management
		protectedAPI.Any("/carts/*path", reverseProxy("cart.core-services.svc.cluster.local:80"))

		// Order management
		protectedAPI.Any("/orders/*path", reverseProxy("order.core-services.svc.cluster.local:80"))

		// Payment processing
		protectedAPI.Any("/payments/*path", reverseProxy("payment.core-services.svc.cluster.local:80"))

		// User management (except login/register)
		protectedAPI.GET("/users", reverseProxy("user-account.user-services.svc.cluster.local:80"))
		protectedAPI.GET("/users/*path", reverseProxy("user-account.user-services.svc.cluster.local:80"))
		protectedAPI.PUT("/users/*path", reverseProxy("user-account.user-services.svc.cluster.local:80"))
		protectedAPI.DELETE("/users/*path", reverseProxy("user-account.user-services.svc.cluster.local:80"))

		// User profiles
		protectedAPI.Any("/profiles/*path", reverseProxy("user-profile.user-services.svc.cluster.local:80"))

		// Wishlists
		protectedAPI.Any("/wishlists/*path", reverseProxy("wishlist.user-services.svc.cluster.local:80"))

		// Review creation/modification
		protectedAPI.POST("/reviews/*path", reverseProxy("review.user-services.svc.cluster.local:80"))
		protectedAPI.PUT("/reviews/*path", reverseProxy("review.user-services.svc.cluster.local:80"))
		protectedAPI.DELETE("/reviews/*path", reverseProxy("review.user-services.svc.cluster.local:80"))

		// Shipping and fulfillment
		protectedAPI.Any("/shipments/*path", reverseProxy("shipping.fulfillment.svc.cluster.local:80"))
		protectedAPI.Any("/returns/*path", reverseProxy("returns.fulfillment.svc.cluster.local:80"))
		protectedAPI.Any("/warehouses/*path", reverseProxy("warehouse.fulfillment.svc.cluster.local:80"))

		// Notifications
		protectedAPI.Any("/notifications/*path", reverseProxy("notification.business-services.svc.cluster.local:80"))

		// Seller management
		protectedAPI.Any("/sellers/*path", reverseProxy("seller.business-services.svc.cluster.local:80"))

		// Events and analytics
		protectedAPI.Any("/events/*path", reverseProxy("event-bus.platform.svc.cluster.local:80"))
		protectedAPI.Any("/analytics/*path", reverseProxy("analytics.platform.svc.cluster.local:80"))
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

func rateLimitMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if cacheClient == nil {
			c.Next()
			return
		}

		clientIP := c.ClientIP()
		key := fmt.Sprintf("ratelimit:%s", clientIP)
		ctx := c.Request.Context()

		// Atomic increment — avoids race condition with GET+SET
		count, err := cacheClient.Incr(ctx, key)
		if err != nil {
			// Valkey unavailable — allow request through
			c.Next()
			return
		}

		// Set TTL on first request in window
		if count == 1 {
			_ = cacheClient.Expire(ctx, key, rateLimitCacheTTL)
		}

		if count > int64(rateLimitMaxReqs) {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "Rate limit exceeded",
				"message": "Too many requests. Please try again later.",
			})
			c.Abort()
			return
		}

		c.Next()
	}
}

func reverseProxy(target string) gin.HandlerFunc {
	return func(c *gin.Context) {
		path := c.Param("path")
		if path == "/" {
			path = ""
		}
		// Build upstream URL: /api/v1/products/PROD-0001 -> product-catalog:80/api/v1/products/PROD-0001
		reqPath := strings.TrimSuffix(c.Request.URL.Path, "/")
		upstreamURL := "http://" + target + reqPath
		if c.Request.URL.RawQuery != "" {
			upstreamURL += "?" + c.Request.URL.RawQuery
		}

		req, err := http.NewRequestWithContext(c.Request.Context(), c.Request.Method, upstreamURL, c.Request.Body)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "failed to create request"})
			return
		}
		for k, v := range c.Request.Header {
			if !strings.EqualFold(k, "Host") {
				req.Header[k] = v
			}
		}

		resp, err := tracedClient.Do(req)
		if err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "upstream unreachable", "target": target})
			return
		}
		defer resp.Body.Close()

		for k, v := range resp.Header {
			for _, vv := range v {
				c.Header(k, vv)
			}
		}
		c.Header("Access-Control-Allow-Origin", "*")
		c.Status(resp.StatusCode)
		io.Copy(c.Writer, resp.Body)
	}
}

const mallLandingHTML = `<!DOCTYPE html>
<html lang="ko">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Region Mall - 멀티리전 쇼핑몰</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Noto Sans KR', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        .header {
            background: rgba(255,255,255,0.95);
            padding: 1rem 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .logo {
            font-size: 1.5rem;
            font-weight: bold;
            color: #667eea;
        }
        .nav a {
            margin-left: 2rem;
            text-decoration: none;
            color: #555;
            font-weight: 500;
        }
        .nav a:hover { color: #667eea; }
        .hero {
            text-align: center;
            padding: 4rem 2rem;
            color: white;
        }
        .hero h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
        }
        .hero p {
            font-size: 1.25rem;
            opacity: 0.9;
            margin-bottom: 2rem;
        }
        .products {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 1.5rem;
            padding: 2rem;
            max-width: 1400px;
            margin: 0 auto;
        }
        .product-card {
            background: white;
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
            transition: transform 0.3s, box-shadow 0.3s;
        }
        .product-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 30px rgba(0,0,0,0.15);
        }
        .product-img {
            width: 100%;
            height: 200px;
            background: linear-gradient(45deg, #f0f0f0, #e0e0e0);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 3rem;
        }
        .product-info {
            padding: 1.5rem;
        }
        .product-name {
            font-size: 1.1rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
            color: #333;
        }
        .product-category {
            font-size: 0.8rem;
            color: #888;
            margin-bottom: 0.5rem;
        }
        .product-price {
            font-size: 1.25rem;
            font-weight: bold;
            color: #667eea;
        }
        .product-seller {
            font-size: 0.85rem;
            color: #666;
            margin-top: 0.5rem;
        }
        .badge {
            display: inline-block;
            padding: 0.25rem 0.5rem;
            background: #ff6b6b;
            color: white;
            border-radius: 4px;
            font-size: 0.75rem;
            margin-bottom: 0.5rem;
        }
        .footer {
            background: rgba(0,0,0,0.2);
            color: white;
            text-align: center;
            padding: 2rem;
            margin-top: 2rem;
        }
    </style>
</head>
<body>
    <header class="header">
        <div class="logo">Multi-Region Mall</div>
        <nav class="nav">
            <a href="#">홈</a>
            <a href="#">카테고리</a>
            <a href="#">베스트</a>
            <a href="#">이벤트</a>
            <a href="#">고객센터</a>
        </nav>
    </header>

    <section class="hero">
        <h1>멀티리전 쇼핑몰에 오신 것을 환영합니다</h1>
        <p>전 세계 어디서나 빠르고 안정적인 쇼핑 경험을 제공합니다</p>
    </section>

    <section class="products">
        <div class="product-card">
            <div class="product-img">📱</div>
            <div class="product-info">
                <span class="badge">BEST</span>
                <div class="product-name">삼성 갤럭시 S25 울트라</div>
                <div class="product-category">electronics</div>
                <div class="product-price">1,890,000원</div>
                <div class="product-seller">삼성전자 Official</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">👟</div>
            <div class="product-info">
                <div class="product-name">나이키 에어맥스 97</div>
                <div class="product-category">shoes</div>
                <div class="product-price">189,000원</div>
                <div class="product-seller">Nike Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">💇</div>
            <div class="product-info">
                <span class="badge">HOT</span>
                <div class="product-name">다이슨 에어랩</div>
                <div class="product-category">beauty</div>
                <div class="product-price">699,000원</div>
                <div class="product-seller">Dyson Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">💻</div>
            <div class="product-info">
                <span class="badge">NEW</span>
                <div class="product-name">애플 맥북 프로 M4</div>
                <div class="product-category">electronics</div>
                <div class="product-price">2,990,000원</div>
                <div class="product-seller">Apple Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">🍳</div>
            <div class="product-info">
                <div class="product-name">르크루제 냄비 세트</div>
                <div class="product-category">kitchen</div>
                <div class="product-price">459,000원</div>
                <div class="product-seller">Le Creuset Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">👟</div>
            <div class="product-info">
                <div class="product-name">아디다스 울트라부스트</div>
                <div class="product-category">shoes</div>
                <div class="product-price">219,000원</div>
                <div class="product-seller">Adidas Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">📺</div>
            <div class="product-info">
                <span class="badge">BEST</span>
                <div class="product-name">LG 올레드 TV 65"</div>
                <div class="product-category">electronics</div>
                <div class="product-price">3,290,000원</div>
                <div class="product-seller">LG전자 Official</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">👜</div>
            <div class="product-info">
                <div class="product-name">무지 캔버스 토트백</div>
                <div class="product-category">fashion</div>
                <div class="product-price">29,000원</div>
                <div class="product-seller">MUJI Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">☕</div>
            <div class="product-info">
                <div class="product-name">스타벅스 텀블러 세트</div>
                <div class="product-category">kitchen</div>
                <div class="product-price">45,000원</div>
                <div class="product-seller">Starbucks Korea</div>
            </div>
        </div>

        <div class="product-card">
            <div class="product-img">🎧</div>
            <div class="product-info">
                <span class="badge">HOT</span>
                <div class="product-name">소니 WH-1000XM5</div>
                <div class="product-category">electronics</div>
                <div class="product-price">429,000원</div>
                <div class="product-seller">Sony Korea</div>
            </div>
        </div>
    </section>

    <footer class="footer">
        <p>Multi-Region Mall - AWS 멀티리전 아키텍처 기반 글로벌 쇼핑몰</p>
        <p style="margin-top: 0.5rem; opacity: 0.8;">© 2026 Multi-Region Mall. All rights reserved.</p>
    </footer>
</body>
</html>`
