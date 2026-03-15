package middleware

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/api-gateway/internal/config"
	"github.com/multi-region-mall/shared/pkg/valkey"
	"go.uber.org/zap"
)

func RateLimit(client *valkey.Client, cfg *config.Config, logger *zap.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Get rate limit key (API key from header or client IP)
		key := c.GetHeader("X-API-Key")
		if key == "" {
			key = c.ClientIP()
		}

		rateLimitKey := fmt.Sprintf("ratelimit:%s", key)

		ctx, cancel := context.WithTimeout(c.Request.Context(), 100*time.Millisecond)
		defer cancel()

		// Token bucket implementation using Valkey
		rdb := client.Redis()
		pipe := rdb.Pipeline()

		// Increment counter
		incrCmd := pipe.Incr(ctx, rateLimitKey)
		// Set expiry on first request
		pipe.Expire(ctx, rateLimitKey, time.Duration(cfg.RateLimitWindow)*time.Second)

		_, err := pipe.Exec(ctx)
		if err != nil {
			logger.Warn("rate limit check failed", zap.Error(err))
			c.Next()
			return
		}

		count := incrCmd.Val()

		// Check if over limit
		limit := int64(cfg.RateLimitRPS * cfg.RateLimitWindow)
		if count > limit {
			c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", limit))
			c.Header("X-RateLimit-Remaining", "0")
			c.Header("Retry-After", fmt.Sprintf("%d", cfg.RateLimitWindow))
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":   "rate limit exceeded",
				"limit":   limit,
				"window":  cfg.RateLimitWindow,
				"retryIn": cfg.RateLimitWindow,
			})
			c.Abort()
			return
		}

		remaining := limit - count
		c.Header("X-RateLimit-Limit", fmt.Sprintf("%d", limit))
		c.Header("X-RateLimit-Remaining", fmt.Sprintf("%d", remaining))

		c.Next()
	}
}
