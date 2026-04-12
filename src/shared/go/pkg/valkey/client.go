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

// Incr atomically increments a key and returns the new value.
func (c *Client) Incr(ctx context.Context, key string) (int64, error) {
	return c.cluster.Incr(ctx, key).Result()
}

// Expire sets a TTL on an existing key.
func (c *Client) Expire(ctx context.Context, key string, ttl time.Duration) error {
	return c.cluster.Expire(ctx, key, ttl).Err()
}

// SetNX sets the key only if it does not exist. Returns true if the key was set.
func (c *Client) SetNX(ctx context.Context, key string, value interface{}, ttl time.Duration) (bool, error) {
	return c.cluster.SetNX(ctx, key, value, ttl).Result()
}

// Eval executes a Lua script atomically.
func (c *Client) Eval(ctx context.Context, script string, keys []string, args ...interface{}) (interface{}, error) {
	return c.cluster.Eval(ctx, script, keys, args...).Result()
}

// DelPattern deletes all keys matching a pattern using SCAN + DEL.
// Use sparingly — SCAN can be slow on large keyspaces.
func (c *Client) DelPattern(ctx context.Context, pattern string) error {
	var cursor uint64
	for {
		keys, next, err := c.cluster.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return err
		}
		if len(keys) > 0 {
			c.cluster.Del(ctx, keys...)
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}
	return nil
}

func (c *Client) Ping(ctx context.Context) error {
	return c.cluster.Ping(ctx).Err()
}

func (c *Client) Close() error {
	return c.cluster.Close()
}
