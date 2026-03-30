package valkey

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"time"

	"github.com/redis/go-redis/extra/redisotel/v9"
	"github.com/redis/go-redis/v9"
)

type Client struct {
	cluster *redis.ClusterClient
}

func New(host string, port int, password string) (*Client, error) {
	opts := &redis.ClusterOptions{
		Addrs:          []string{fmt.Sprintf("%s:%d", host, port)},
		ReadTimeout:    3 * time.Second,
		WriteTimeout:   3 * time.Second,
		PoolSize:       20,
		RouteByLatency: true, // Prefer same-AZ replicas for reads
		TLSConfig:      &tls.Config{},
	}
	if password != "" {
		opts.Password = password
	}
	cluster := redis.NewClusterClient(opts)

	// Add OTel tracing for automatic Redis span creation
	if err := redisotel.InstrumentTracing(cluster); err != nil {
		log.Printf("valkey: failed to instrument tracing: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := cluster.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("valkey connect: %w", err)
	}

	return &Client{cluster: cluster}, nil
}

func (c *Client) Get(ctx context.Context, key string) (string, error) {
	return c.cluster.Get(ctx, key).Result()
}

func (c *Client) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	return c.cluster.Set(ctx, key, value, ttl).Err()
}

func (c *Client) Del(ctx context.Context, keys ...string) error {
	return c.cluster.Del(ctx, keys...).Err()
}

func (c *Client) Ping(ctx context.Context) error {
	return c.cluster.Ping(ctx).Err()
}

func (c *Client) Close() error {
	return c.cluster.Close()
}
