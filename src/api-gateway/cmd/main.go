package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/api-gateway/internal/config"
	"github.com/multi-region-mall/api-gateway/internal/handler"
	"github.com/multi-region-mall/api-gateway/internal/middleware"
	"github.com/multi-region-mall/api-gateway/internal/routes"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
	"go.uber.org/zap"
)

func main() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	cfg := config.Load()
	logger.Info("starting api-gateway",
		zap.String("region", cfg.AWSRegion),
		zap.String("role", cfg.RegionRole),
	)

	tp, err := tracing.InitTracer(context.Background(), "api-gateway")
	if err != nil {
		logger.Warn("failed to init tracer", zap.Error(err))
	} else {
		defer tp.Shutdown(context.Background())
	}

	// Initialize Valkey for rate limiting
	valkeyClient, err := valkey.New(cfg.CacheHost, cfg.CachePort)
	if err != nil {
		logger.Warn("valkey not available, rate limiting disabled", zap.Error(err))
	}

	healthChecker := health.New()

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(tracing.GinMiddleware("api-gateway"))
	r.Use(middleware.JSONLogger(logger))

	healthChecker.RegisterRoutes(r)

	// Rate limiting middleware (if Valkey is available)
	if valkeyClient != nil {
		r.Use(middleware.RateLimit(valkeyClient, cfg, logger))
	}

	// Region write forwarding middleware
	r.Use(middleware.RegionForward(cfg))

	// Setup reverse proxy routes
	routeMap := routes.GetRouteMap()
	proxyHandler := handler.NewProxyHandler(routeMap, logger)
	r.Any("/api/v1/*path", proxyHandler.Handle)

	healthChecker.SetStarted(true)
	healthChecker.SetReady(true)

	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
	}

	go func() {
		logger.Info("listening", zap.String("port", cfg.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("listen failed", zap.Error(err))
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting down")
	healthChecker.SetReady(false)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Error("shutdown error", zap.Error(err))
	}

	if valkeyClient != nil {
		valkeyClient.Close()
	}

	logger.Info("server stopped")
}
