package aurora

import (
	"context"
	"fmt"
	"net/url"
	"os/exec"
	"strings"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/multi-region-mall/shared/pkg/config"
)

type Client struct {
	Pool *pgxpool.Pool
}

func New(ctx context.Context, cfg *config.Config) (*Client, error) {
	var dsn string

	// Check if this is a DSQL endpoint (*.dsql.*.on.aws)
	if strings.Contains(cfg.DBHost, ".dsql.") {
		token, err := generateDSQLToken(ctx, cfg.DBHost, cfg.AWSRegion)
		if err != nil {
			return nil, fmt.Errorf("dsql token: %w", err)
		}
		dsn = fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=require",
			"admin", url.PathEscape(token), cfg.DBHost, cfg.DBPort, "postgres")
	} else {
		dsn = fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=require",
			url.PathEscape(cfg.DBUser), url.PathEscape(cfg.DBPassword), cfg.DBHost, cfg.DBPort, cfg.DBName)
	}

	pgxConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("aurora parse config: %w", err)
	}

	// Add OTel tracing for automatic PostgreSQL span creation
	pgxConfig.ConnConfig.Tracer = otelpgx.NewTracer()

	pool, err := pgxpool.NewWithConfig(ctx, pgxConfig)
	if err != nil {
		return nil, fmt.Errorf("aurora connect: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("aurora ping: %w", err)
	}

	return &Client{Pool: pool}, nil
}

func generateDSQLToken(ctx context.Context, hostname, region string) (string, error) {
	cmd := exec.CommandContext(ctx, "aws", "dsql", "generate-db-connect-admin-auth-token",
		"--hostname", hostname, "--region", region)
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("aws dsql generate token: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (c *Client) Close() {
	c.Pool.Close()
}

func (c *Client) Ping(ctx context.Context) error {
	return c.Pool.Ping(ctx)
}
