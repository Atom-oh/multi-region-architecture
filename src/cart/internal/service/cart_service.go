package service

import (
	"context"

	"github.com/multi-region-mall/cart/internal/model"
	"github.com/multi-region-mall/cart/internal/repository"
)

type CartService struct {
	repo *repository.CartRepository
}

func NewCartService(repo *repository.CartRepository) *CartService {
	return &CartService{repo: repo}
}

func (s *CartService) GetCart(ctx context.Context, userID string) (*model.Cart, error) {
	return s.repo.GetCart(ctx, userID)
}

func (s *CartService) AddItem(ctx context.Context, userID string, req model.AddItemRequest) (*model.CartItem, error) {
	item := model.CartItem{
		ProductID: req.ProductID,
		SKU:       req.SKU,
		Name:      req.Name,
		Price:     req.Price,
		Quantity:  req.Quantity,
	}
	return s.repo.AddItem(ctx, userID, item)
}

func (s *CartService) UpdateItem(ctx context.Context, userID, itemID string, quantity int) (*model.CartItem, error) {
	if quantity == 0 {
		err := s.repo.RemoveItem(ctx, userID, itemID)
		return nil, err
	}
	return s.repo.UpdateItem(ctx, userID, itemID, quantity)
}

func (s *CartService) RemoveItem(ctx context.Context, userID, itemID string) error {
	return s.repo.RemoveItem(ctx, userID, itemID)
}

func (s *CartService) ClearCart(ctx context.Context, userID string) error {
	return s.repo.ClearCart(ctx, userID)
}
