package aurora

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/multi-region-mall/shared/pkg/config"
)

type Client struct {
	Pool *pgxpool.Pool
}

func New(ctx context.Context, cfg *config.Config) (*Client, error) {
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=require",
		cfg.DBUser, cfg.DBPassword, cfg.DBHost, cfg.DBPort, cfg.DBName)

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("aurora connect: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("aurora ping: %w", err)
	}

	return &Client{Pool: pool}, nil
}

func (c *Client) Close() {
	c.Pool.Close()
}

func (c *Client) Ping(ctx context.Context) error {
	return c.Pool.Ping(ctx)
}
