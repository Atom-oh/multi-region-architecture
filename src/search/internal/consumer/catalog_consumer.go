package consumer

import (
	"context"
	"encoding/json"

	kafkago "github.com/segmentio/kafka-go"
	"go.uber.org/zap"

	"github.com/multi-region-mall/search/internal/repository"
	"github.com/multi-region-mall/search/internal/service"
	"github.com/multi-region-mall/shared/pkg/kafka"
)

type CatalogConsumer struct {
	consumers []*kafka.Consumer
	service   *service.SearchService
	logger    *zap.Logger
}

func NewCatalogConsumer(brokers string, service *service.SearchService, logger *zap.Logger) *CatalogConsumer {
	c := &CatalogConsumer{
		service: service,
		logger:  logger,
	}

	topics := []string{"catalog.product.created", "catalog.product.updated", "catalog.product.deleted"}
	for _, topic := range topics {
		consumer := kafka.NewConsumer(brokers, topic, "search-indexer", c.handleMessage, logger)
		c.consumers = append(c.consumers, consumer)
	}

	return c
}

func (c *CatalogConsumer) Start(ctx context.Context) {
	for _, consumer := range c.consumers {
		go consumer.Start(ctx)
	}
}

func (c *CatalogConsumer) Close() error {
	for _, consumer := range c.consumers {
		if err := consumer.Close(); err != nil {
			c.logger.Error("failed to close consumer", zap.Error(err))
		}
	}
	return nil
}

func (c *CatalogConsumer) handleMessage(ctx context.Context, msg kafkago.Message) error {
	var event struct {
		Event     string          `json:"event"`
		Product   json.RawMessage `json:"product"`
		ProductID string          `json:"product_id"`
	}

	if err := json.Unmarshal(msg.Value, &event); err != nil {
		c.logger.Error("failed to unmarshal event", zap.Error(err))
		return err
	}

	switch event.Event {
	case "product.created", "product.updated":
		var product repository.Product
		if err := json.Unmarshal(event.Product, &product); err != nil {
			c.logger.Error("failed to unmarshal product", zap.Error(err))
			return err
		}
		if err := c.service.IndexProduct(ctx, product); err != nil {
			c.logger.Error("failed to index product", zap.String("id", product.ID), zap.Error(err))
			return err
		}
		c.logger.Info("indexed product", zap.String("id", product.ID), zap.String("event", event.Event))

	case "product.deleted":
		if err := c.service.DeleteProduct(ctx, event.ProductID); err != nil {
			c.logger.Error("failed to delete product", zap.String("id", event.ProductID), zap.Error(err))
			return err
		}
		c.logger.Info("deleted product from index", zap.String("id", event.ProductID))
	}

	return nil
}
