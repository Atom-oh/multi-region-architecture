package aurora

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

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

	// Connection pool tuning — defaults safe for DSQL (~500 conn limit)
	pgxConfig.MaxConns = int32(envInt("DB_MAX_CONNS", 25))
	pgxConfig.MinConns = int32(envInt("DB_MIN_CONNS", 5))
	pgxConfig.MaxConnLifetime = 30 * time.Minute
	pgxConfig.MaxConnIdleTime = 5 * time.Minute
	pgxConfig.HealthCheckPeriod = 1 * time.Minute

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

// GetWriteDSN returns a connection string targeting the writer endpoint.
// Uses DB_WRITE_HOST if set, otherwise falls back to DB_HOST.
func GetWriteDSN(cfg *config.Config) string {
	host := cfg.DBWriteHost
	if host == "" {
		host = cfg.DBHost
	}
	if strings.Contains(host, ".dsql.") {
		return "" // DSQL uses token auth, not static DSN
	}
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=require",
		url.PathEscape(cfg.DBUser), url.PathEscape(cfg.DBPassword), host, cfg.DBPort, cfg.DBName)
}

// GetReadDSN returns a connection string targeting the AZ-local reader endpoint.
// Uses DB_READ_HOST_LOCAL if set, otherwise falls back to DB_HOST.
func GetReadDSN(cfg *config.Config) string {
	host := cfg.DBReadHostLocal
	if host == "" {
		host = cfg.DBHost
	}
	if strings.Contains(host, ".dsql.") {
		return "" // DSQL uses token auth, not static DSN
	}
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=require",
		url.PathEscape(cfg.DBUser), url.PathEscape(cfg.DBPassword), host, cfg.DBPort, cfg.DBName)
}

func (c *Client) Close() {
	c.Pool.Close()
}

func (c *Client) Ping(ctx context.Context) error {
	return c.Pool.Ping(ctx)
}

func envInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}
