package model

import "time"

type Inventory struct {
	SKU       string    `json:"sku"`
	Available int       `json:"available"`
	Reserved  int       `json:"reserved"`
	Total     int       `json:"total"`
	UpdatedAt time.Time `json:"updated_at"`
}

type ReserveRequest struct {
	Quantity int `json:"quantity" binding:"required,min=1"`
}

type ReleaseRequest struct {
	Quantity int `json:"quantity" binding:"required,min=1"`
}

type UpdateStockRequest struct {
	Available int `json:"available" binding:"min=0"`
	Total     int `json:"total" binding:"min=0"`
}
