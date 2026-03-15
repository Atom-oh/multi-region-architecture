package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"

	"github.com/multi-region-mall/cart/internal/config"
	"github.com/multi-region-mall/cart/internal/handler"
	"github.com/multi-region-mall/cart/internal/middleware"
	"github.com/multi-region-mall/cart/internal/repository"
	"github.com/multi-region-mall/cart/internal/service"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

func main() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	cfg := config.Load()
	logger.Info("starting cart service", zap.String("region", cfg.AWSRegion))

	tp, err := tracing.InitTracer(context.Background(), "cart")
	if err != nil {
		logger.Warn("failed to init tracer", zap.Error(err))
	} else {
		defer tp.Shutdown(context.Background())
	}

	// Initialize Valkey (primary data store for cart)
	valkeyClient, err := valkey.New(cfg.CacheHost, cfg.CachePort)
	if err != nil {
		logger.Fatal("failed to connect to valkey", zap.Error(err))
	}
	defer valkeyClient.Close()

	// Initialize repository and service
	cartRepo := repository.NewCartRepository(valkeyClient)
	cartService := service.NewCartService(cartRepo)

	// Initialize health checker
	healthChecker := health.New()
	healthChecker.SetStarted(true)

	// Setup Gin router
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(tracing.GinMiddleware("cart"))
	r.Use(middleware.RegionWriteMiddleware(cfg))

	// Register handlers
	healthHandler := handler.NewHealthHandler(healthChecker)
	healthHandler.RegisterRoutes(r)

	cartHandler := handler.NewCartHandler(cartService)
	cartHandler.RegisterRoutes(r)

	// Set ready
	healthChecker.SetReady(true)

	// Start server
	srv := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: r,
	}

	go func() {
		logger.Info("server listening", zap.String("port", cfg.Port))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatal("server error", zap.Error(err))
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting down server")
	healthChecker.SetReady(false)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("server shutdown error", zap.Error(err))
	}

	logger.Info("server stopped")
}
