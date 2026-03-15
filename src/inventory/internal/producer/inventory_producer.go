package producer

import (
	"context"

	"go.uber.org/zap"

	"github.com/multi-region-mall/inventory/internal/model"
	"github.com/multi-region-mall/shared/pkg/kafka"
)

type InventoryProducer struct {
	reservedProducer *kafka.Producer
	releasedProducer *kafka.Producer
	updatedProducer  *kafka.Producer
	logger           *zap.Logger
}

func NewInventoryProducer(brokers string, logger *zap.Logger) *InventoryProducer {
	return &InventoryProducer{
		reservedProducer: kafka.NewProducer(brokers, "inventory.reserved", logger),
		releasedProducer: kafka.NewProducer(brokers, "inventory.released", logger),
		updatedProducer:  kafka.NewProducer(brokers, "inventory.updated", logger),
		logger:           logger,
	}
}

func (p *InventoryProducer) PublishReserved(ctx context.Context, sku string, quantity int, inv *model.Inventory) {
	event := map[string]interface{}{
		"event":     "inventory.reserved",
		"sku":       sku,
		"quantity":  quantity,
		"inventory": inv,
	}
	if err := p.reservedProducer.Publish(ctx, sku, event); err != nil {
		p.logger.Error("failed to publish inventory.reserved", zap.String("sku", sku), zap.Error(err))
	}
}

func (p *InventoryProducer) PublishReleased(ctx context.Context, sku string, quantity int, inv *model.Inventory) {
	event := map[string]interface{}{
		"event":     "inventory.released",
		"sku":       sku,
		"quantity":  quantity,
		"inventory": inv,
	}
	if err := p.releasedProducer.Publish(ctx, sku, event); err != nil {
		p.logger.Error("failed to publish inventory.released", zap.String("sku", sku), zap.Error(err))
	}
}

func (p *InventoryProducer) PublishUpdated(ctx context.Context, sku string, inv *model.Inventory) {
	event := map[string]interface{}{
		"event":     "inventory.updated",
		"sku":       sku,
		"inventory": inv,
	}
	if err := p.updatedProducer.Publish(ctx, sku, event); err != nil {
		p.logger.Error("failed to publish inventory.updated", zap.String("sku", sku), zap.Error(err))
	}
}

func (p *InventoryProducer) Close() error {
	var errs []error
	if err := p.reservedProducer.Close(); err != nil {
		errs = append(errs, err)
	}
	if err := p.releasedProducer.Close(); err != nil {
		errs = append(errs, err)
	}
	if err := p.updatedProducer.Close(); err != nil {
		errs = append(errs, err)
	}
	if len(errs) > 0 {
		return errs[0]
	}
	return nil
}
