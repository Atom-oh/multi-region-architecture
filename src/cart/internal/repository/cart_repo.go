package repository

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/multi-region-mall/cart/internal/model"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

const cartTTL = 7 * 24 * time.Hour // 7 days

type CartRepository struct {
	client *valkey.Client
}

func NewCartRepository(client *valkey.Client) *CartRepository {
	return &CartRepository{client: client}
}

func (r *CartRepository) cartKey(userID string) string {
	return fmt.Sprintf("cart:%s", userID)
}

func (r *CartRepository) GetCart(ctx context.Context, userID string) (*model.Cart, error) {
	key := r.cartKey(userID)
	rdb := r.client.Redis()

	data, err := rdb.HGetAll(ctx, key).Result()
	if err != nil {
		return nil, fmt.Errorf("get cart: %w", err)
	}

	cart := &model.Cart{
		UserID:    userID,
		Items:     []model.CartItem{},
		UpdatedAt: time.Now(),
	}

	for itemID, itemJSON := range data {
		var item model.CartItem
		if err := json.Unmarshal([]byte(itemJSON), &item); err != nil {
			continue
		}
		item.ItemID = itemID
		cart.Items = append(cart.Items, item)
		cart.Total += item.Price * float64(item.Quantity)
		cart.ItemCount += item.Quantity
	}

	return cart, nil
}

func (r *CartRepository) AddItem(ctx context.Context, userID string, item model.CartItem) (*model.CartItem, error) {
	key := r.cartKey(userID)
	rdb := r.client.Redis()

	item.ItemID = uuid.New().String()
	item.AddedAt = time.Now()

	itemJSON, err := json.Marshal(item)
	if err != nil {
		return nil, fmt.Errorf("marshal item: %w", err)
	}

	pipe := rdb.Pipeline()
	pipe.HSet(ctx, key, item.ItemID, itemJSON)
	pipe.Expire(ctx, key, cartTTL)
	_, err = pipe.Exec(ctx)
	if err != nil {
		return nil, fmt.Errorf("add item: %w", err)
	}

	return &item, nil
}

func (r *CartRepository) UpdateItem(ctx context.Context, userID, itemID string, quantity int) (*model.CartItem, error) {
	key := r.cartKey(userID)
	rdb := r.client.Redis()

	itemJSON, err := rdb.HGet(ctx, key, itemID).Result()
	if err == redis.Nil {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("get item: %w", err)
	}

	var item model.CartItem
	if err := json.Unmarshal([]byte(itemJSON), &item); err != nil {
		return nil, fmt.Errorf("unmarshal item: %w", err)
	}

	item.ItemID = itemID
	item.Quantity = quantity

	updatedJSON, err := json.Marshal(item)
	if err != nil {
		return nil, fmt.Errorf("marshal item: %w", err)
	}

	pipe := rdb.Pipeline()
	pipe.HSet(ctx, key, itemID, updatedJSON)
	pipe.Expire(ctx, key, cartTTL)
	_, err = pipe.Exec(ctx)
	if err != nil {
		return nil, fmt.Errorf("update item: %w", err)
	}

	return &item, nil
}

func (r *CartRepository) RemoveItem(ctx context.Context, userID, itemID string) error {
	key := r.cartKey(userID)
	rdb := r.client.Redis()

	deleted, err := rdb.HDel(ctx, key, itemID).Result()
	if err != nil {
		return fmt.Errorf("remove item: %w", err)
	}
	if deleted == 0 {
		return nil
	}

	return nil
}

func (r *CartRepository) ClearCart(ctx context.Context, userID string) error {
	key := r.cartKey(userID)
	rdb := r.client.Redis()

	if err := rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("clear cart: %w", err)
	}

	return nil
}
