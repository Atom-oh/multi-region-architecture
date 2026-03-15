package main

import (
	"context"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/event-bus/internal/config"
	"github.com/multi-region-mall/event-bus/internal/handler"
	"github.com/multi-region-mall/event-bus/internal/middleware"
	"github.com/multi-region-mall/event-bus/internal/producer"
	"github.com/multi-region-mall/event-bus/internal/service"
	"github.com/multi-region-mall/shared/pkg/health"
	"github.com/multi-region-mall/shared/pkg/tracing"
	"go.uber.org/zap"
)

func main() {
	logger, _ := zap.NewProduction()
	defer logger.Sync()

	cfg := config.Load()
	logger.Info("starting event-bus",
		zap.String("region", cfg.AWSRegion),
		zap.String("role", cfg.RegionRole),
	)

	tp, err := tracing.InitTracer(context.Background(), "event-bus")
	if err != nil {
		logger.Warn("failed to init tracer", zap.Error(err))
	} else {
		defer tp.Shutdown(context.Background())
	}

	// Initialize Kafka producer
	eventProducer := producer.NewEventProducer(cfg.KafkaBrokers, logger)

	// Initialize event service
	eventService := service.NewEventService(eventProducer, logger)

	healthChecker := health.New()

	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(tracing.GinMiddleware("event-bus"))
	r.Use(middleware.JSONLogger(logger))

	healthChecker.RegisterRoutes(r)

	// Region write forwarding middleware
	r.Use(middleware.RegionForward(cfg))

	// Event handlers
	eventHandler := handler.NewEventsHandler(eventService, logger)
	api := r.Group("/api/v1")
	{
		api.POST("/events", eventHandler.PublishEvent)
		api.GET("/events/topics", eventHandler.ListTopics)
		api.GET("/events/dlq", eventHandler.ListDLQ)
		api.POST("/events/dlq/:id/retry", eventHandler.RetryDLQ)
	}

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

	eventProducer.Close()

	logger.Info("server stopped")
}
