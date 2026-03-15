package repository

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/multi-region-mall/inventory/internal/model"
)

var (
	ErrNotFound          = errors.New("inventory not found")
	ErrInsufficientStock = errors.New("insufficient stock")
)

type InventoryRepository struct {
	pool *pgxpool.Pool
}

func NewInventoryRepository(pool *pgxpool.Pool) *InventoryRepository {
	return &InventoryRepository{pool: pool}
}

func (r *InventoryRepository) GetBySKU(ctx context.Context, sku string) (*model.Inventory, error) {
	query := `SELECT sku, available, reserved, total, updated_at FROM inventory WHERE sku = $1`

	var inv model.Inventory
	err := r.pool.QueryRow(ctx, query, sku).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("query inventory: %w", err)
	}

	return &inv, nil
}

func (r *InventoryRepository) Reserve(ctx context.Context, sku string, quantity int) (*model.Inventory, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Lock the row for update
	query := `SELECT sku, available, reserved, total, updated_at FROM inventory WHERE sku = $1 FOR UPDATE`

	var inv model.Inventory
	err = tx.QueryRow(ctx, query, sku).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("select for update: %w", err)
	}

	if inv.Available < quantity {
		return nil, ErrInsufficientStock
	}

	// Update inventory
	updateQuery := `
		UPDATE inventory
		SET available = available - $1, reserved = reserved + $1, updated_at = NOW()
		WHERE sku = $2
		RETURNING sku, available, reserved, total, updated_at`

	err = tx.QueryRow(ctx, updateQuery, quantity, sku).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("update inventory: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}

	return &inv, nil
}

func (r *InventoryRepository) Release(ctx context.Context, sku string, quantity int) (*model.Inventory, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	// Lock the row for update
	query := `SELECT sku, available, reserved, total, updated_at FROM inventory WHERE sku = $1 FOR UPDATE`

	var inv model.Inventory
	err = tx.QueryRow(ctx, query, sku).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("select for update: %w", err)
	}

	// Cap release quantity at reserved amount
	releaseQty := quantity
	if releaseQty > inv.Reserved {
		releaseQty = inv.Reserved
	}

	// Update inventory
	updateQuery := `
		UPDATE inventory
		SET available = available + $1, reserved = reserved - $1, updated_at = NOW()
		WHERE sku = $2
		RETURNING sku, available, reserved, total, updated_at`

	err = tx.QueryRow(ctx, updateQuery, releaseQty, sku).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("update inventory: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("commit tx: %w", err)
	}

	return &inv, nil
}

func (r *InventoryRepository) UpdateStock(ctx context.Context, sku string, available, total int) (*model.Inventory, error) {
	query := `
		INSERT INTO inventory (sku, available, reserved, total, updated_at)
		VALUES ($1, $2, 0, $3, NOW())
		ON CONFLICT (sku) DO UPDATE
		SET available = $2, total = $3, updated_at = NOW()
		RETURNING sku, available, reserved, total, updated_at`

	var inv model.Inventory
	err := r.pool.QueryRow(ctx, query, sku, available, total).Scan(
		&inv.SKU,
		&inv.Available,
		&inv.Reserved,
		&inv.Total,
		&inv.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("upsert inventory: %w", err)
	}

	return &inv, nil
}

func (r *InventoryRepository) Ping(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	return r.pool.Ping(ctx)
}
