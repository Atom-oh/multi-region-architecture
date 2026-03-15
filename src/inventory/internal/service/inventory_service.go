package service

import (
	"context"
	"encoding/json"
	"time"

	"go.uber.org/zap"

	"github.com/multi-region-mall/inventory/internal/model"
	"github.com/multi-region-mall/inventory/internal/producer"
	"github.com/multi-region-mall/inventory/internal/repository"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

const cacheTTL = 30 * time.Second

type InventoryService struct {
	repo     *repository.InventoryRepository
	cache    *valkey.Client
	producer *producer.InventoryProducer
	logger   *zap.Logger
}

func NewInventoryService(
	repo *repository.InventoryRepository,
	cache *valkey.Client,
	producer *producer.InventoryProducer,
	logger *zap.Logger,
) *InventoryService {
	return &InventoryService{
		repo:     repo,
		cache:    cache,
		producer: producer,
		logger:   logger,
	}
}

func (s *InventoryService) cacheKey(sku string) string {
	return "inventory:" + sku
}

func (s *InventoryService) GetStock(ctx context.Context, sku string) (*model.Inventory, error) {
	// Try cache first
	cacheKey := s.cacheKey(sku)
	if cached, err := s.cache.Get(ctx, cacheKey); err == nil && cached != "" {
		var inv model.Inventory
		if err := json.Unmarshal([]byte(cached), &inv); err == nil {
			return &inv, nil
		}
	}

	// Fetch from database
	inv, err := s.repo.GetBySKU(ctx, sku)
	if err != nil {
		return nil, err
	}

	// Cache result
	if data, err := json.Marshal(inv); err == nil {
		_ = s.cache.Set(ctx, cacheKey, string(data), cacheTTL)
	}

	return inv, nil
}

func (s *InventoryService) Reserve(ctx context.Context, sku string, quantity int) (*model.Inventory, error) {
	inv, err := s.repo.Reserve(ctx, sku, quantity)
	if err != nil {
		return nil, err
	}

	// Invalidate cache
	_ = s.cache.Del(ctx, s.cacheKey(sku))

	// Publish event
	if s.producer != nil {
		s.producer.PublishReserved(ctx, sku, quantity, inv)
	}

	s.logger.Info("reserved inventory", zap.String("sku", sku), zap.Int("quantity", quantity))
	return inv, nil
}

func (s *InventoryService) Release(ctx context.Context, sku string, quantity int) (*model.Inventory, error) {
	inv, err := s.repo.Release(ctx, sku, quantity)
	if err != nil {
		return nil, err
	}

	// Invalidate cache
	_ = s.cache.Del(ctx, s.cacheKey(sku))

	// Publish event
	if s.producer != nil {
		s.producer.PublishReleased(ctx, sku, quantity, inv)
	}

	s.logger.Info("released inventory", zap.String("sku", sku), zap.Int("quantity", quantity))
	return inv, nil
}

func (s *InventoryService) UpdateStock(ctx context.Context, sku string, available, total int) (*model.Inventory, error) {
	inv, err := s.repo.UpdateStock(ctx, sku, available, total)
	if err != nil {
		return nil, err
	}

	// Invalidate cache
	_ = s.cache.Del(ctx, s.cacheKey(sku))

	// Publish event
	if s.producer != nil {
		s.producer.PublishUpdated(ctx, sku, inv)
	}

	s.logger.Info("updated inventory", zap.String("sku", sku), zap.Int("available", available), zap.Int("total", total))
	return inv, nil
}
