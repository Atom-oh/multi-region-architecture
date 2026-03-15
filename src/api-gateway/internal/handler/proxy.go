package handler

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type ProxyHandler struct {
	routeMap map[string]string
	proxies  map[string]*httputil.ReverseProxy
	logger   *zap.Logger
}

func NewProxyHandler(routeMap map[string]string, logger *zap.Logger) *ProxyHandler {
	proxies := make(map[string]*httputil.ReverseProxy)

	for prefix, target := range routeMap {
		targetURL, err := url.Parse("http://" + target)
		if err != nil {
			logger.Error("invalid target URL", zap.String("target", target), zap.Error(err))
			continue
		}

		proxy := httputil.NewSingleHostReverseProxy(targetURL)
		proxy.Director = func(original *http.Request) func(*http.Request) {
			return func(req *http.Request) {
				req.URL.Scheme = targetURL.Scheme
				req.URL.Host = targetURL.Host
				req.Host = targetURL.Host
				// Preserve the original path after the prefix
				if original.URL.RawQuery != "" {
					req.URL.RawQuery = original.URL.RawQuery
				}
			}
		}(nil)

		proxies[prefix] = proxy
	}

	return &ProxyHandler{
		routeMap: routeMap,
		proxies:  proxies,
		logger:   logger,
	}
}

func (h *ProxyHandler) Handle(c *gin.Context) {
	path := c.Param("path")
	fullPath := "/api/v1" + path

	// Find matching route prefix
	for prefix, target := range h.routeMap {
		if strings.HasPrefix(fullPath, prefix) {
			targetURL, err := url.Parse("http://" + target)
			if err != nil {
				h.logger.Error("invalid target URL", zap.String("target", target), zap.Error(err))
				c.JSON(http.StatusBadGateway, gin.H{"error": "invalid upstream"})
				return
			}

			proxy := httputil.NewSingleHostReverseProxy(targetURL)
			proxy.Director = func(req *http.Request) {
				req.URL.Scheme = targetURL.Scheme
				req.URL.Host = targetURL.Host
				req.Host = targetURL.Host
				req.URL.Path = fullPath
				req.URL.RawQuery = c.Request.URL.RawQuery
			}

			proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
				h.logger.Error("proxy error",
					zap.String("target", target),
					zap.String("path", fullPath),
					zap.Error(err),
				)
				w.WriteHeader(http.StatusBadGateway)
				w.Write([]byte(`{"error":"upstream unavailable"}`))
			}

			h.logger.Debug("proxying request",
				zap.String("path", fullPath),
				zap.String("target", target),
			)

			proxy.ServeHTTP(c.Writer, c.Request)
			return
		}
	}

	c.JSON(http.StatusNotFound, gin.H{"error": "no route found"})
}
