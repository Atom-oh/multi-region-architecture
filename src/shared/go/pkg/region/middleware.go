package region

import (
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/tracing"
)

func WriteForwardMiddleware(cfg *config.Config) gin.HandlerFunc {
	client := tracing.HTTPClient()
	client.Timeout = 30 * time.Second

	return func(c *gin.Context) {
		if cfg.IsPrimary() {
			c.Next()
			return
		}

		// In secondary region, forward write operations to primary
		if isWriteMethod(c.Request.Method) && cfg.PrimaryHost != "" {
			forwardToPrimary(c, cfg.PrimaryHost, client)
			c.Abort()
			return
		}

		c.Next()
	}
}

func isWriteMethod(method string) bool {
	switch method {
	case http.MethodPost, http.MethodPut, http.MethodPatch, http.MethodDelete:
		return true
	}
	return false
}

func forwardToPrimary(c *gin.Context, primaryHost string, client *http.Client) {
	targetURL := primaryHost + c.Request.RequestURI

	req, err := http.NewRequestWithContext(c.Request.Context(), c.Request.Method, targetURL, c.Request.Body)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to create forward request"})
		return
	}

	for k, v := range c.Request.Header {
		req.Header[k] = v
	}
	req.Header.Set("X-Forwarded-From-Region", c.GetString("aws_region"))

	resp, err := client.Do(req)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to forward to primary"})
		return
	}
	defer resp.Body.Close()

	for k, v := range resp.Header {
		for _, val := range v {
			c.Header(k, val)
		}
	}
	c.Status(resp.StatusCode)
	io.Copy(c.Writer, resp.Body)
}
