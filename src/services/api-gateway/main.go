package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

func main() {
	cfg := config.Load("api-gateway")

	r := gin.Default()
	r.Use(tracing.GinMiddleware(cfg.ServiceName))

	hc := health.New()
	hc.RegisterRoutes(r)

	// Root route - returns coming soon HTML page (also used by K8s probes)
	r.GET("/", func(c *gin.Context) {
		c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(comingSoonHTML))
	})

	// API health endpoint
	r.GET("/api/v1/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": cfg.ServiceName,
			"region":  cfg.AWSRegion,
		})
	})

	// Proxy routes to backend services (stub responses)
	api := r.Group("/api/v1")
	{
		api.Any("/products/*path", proxyHandler("product-catalog-service"))
		api.Any("/inventory/*path", proxyHandler("inventory-service"))
		api.Any("/carts/*path", proxyHandler("cart-service"))
		api.Any("/search/*path", proxyHandler("search-service"))
		api.Any("/orders/*path", proxyHandler("order-service"))
		api.Any("/users/*path", proxyHandler("user-service"))
		api.Any("/events/*path", proxyHandler("event-bus"))
	}

	hc.SetStarted(true)
	hc.SetReady(true)
	r.Run(":" + cfg.Port)
}

func proxyHandler(service string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Stub response - in production this would proxy to the actual service
		c.JSON(http.StatusOK, gin.H{
			"message":      "proxied to " + service,
			"path":         c.Param("path"),
			"stub_response": true,
		})
	}
}

const comingSoonHTML = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Region Mall - Coming Soon</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: #fff;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            background: linear-gradient(90deg, #e94560, #ff6b6b);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }
        p {
            font-size: 1.25rem;
            color: #a0a0a0;
            margin-bottom: 2rem;
        }
        .status {
            display: inline-block;
            padding: 0.5rem 1rem;
            background: rgba(233, 69, 96, 0.2);
            border: 1px solid #e94560;
            border-radius: 20px;
            font-size: 0.875rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Multi-Region Mall</h1>
        <p>Your global shopping destination is coming soon</p>
        <span class="status">Under Construction</span>
    </div>
</body>
</html>`
