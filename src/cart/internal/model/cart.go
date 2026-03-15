package model

import "time"

type CartItem struct {
	ItemID    string    `json:"item_id"`
	ProductID string    `json:"product_id"`
	SKU       string    `json:"sku"`
	Name      string    `json:"name"`
	Price     float64   `json:"price"`
	Quantity  int       `json:"quantity"`
	AddedAt   time.Time `json:"added_at"`
}

type Cart struct {
	UserID    string     `json:"user_id"`
	Items     []CartItem `json:"items"`
	Total     float64    `json:"total"`
	ItemCount int        `json:"item_count"`
	UpdatedAt time.Time  `json:"updated_at"`
}

type AddItemRequest struct {
	ProductID string  `json:"product_id" binding:"required"`
	SKU       string  `json:"sku" binding:"required"`
	Name      string  `json:"name" binding:"required"`
	Price     float64 `json:"price" binding:"required"`
	Quantity  int     `json:"quantity" binding:"required,min=1"`
}

type UpdateItemRequest struct {
	Quantity int `json:"quantity" binding:"required,min=0"`
}
