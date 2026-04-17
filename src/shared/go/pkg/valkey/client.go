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
	reader *redis.ClusterClient
	writer *redis.ClusterClient
}

func newCluster(host string, port int, password string, routeByLatency bool) (*redis.ClusterClient, error) {
	opts := &redis.ClusterOptions{
		Addrs:          []string{fmt.Sprintf("%s:%d", host, port)},
		ReadTimeout:    3 * time.Second,
		WriteTimeout:   3 * time.Second,
		PoolSize:       20,
		RouteByLatency: routeByLatency,
		TLSConfig:      &tls.Config{},
	}
	if password != "" {
		opts.Password = password
	}
	cluster := redis.NewClusterClient(opts)

	if err := redisotel.InstrumentTracing(cluster); err != nil {
		log.Printf("valkey: failed to instrument tracing: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := cluster.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("valkey connect: %w", err)
	}

	return cluster, nil
}

// New creates a client with a single endpoint for both reads and writes.
func New(host string, port int, password string) (*Client, error) {
	cluster, err := newCluster(host, port, password, true)
	if err != nil {
		return nil, err
	}
	return &Client{reader: cluster, writer: cluster}, nil
}

// NewWithWriter creates a client with separate read and write endpoints.
// Reads go to the local (secondary) cluster; writes go to the primary cluster.
func NewWithWriter(readHost string, writeHost string, port int, password string) (*Client, error) {
	reader, err := newCluster(readHost, port, password, true)
	if err != nil {
		return nil, fmt.Errorf("valkey reader: %w", err)
	}
	writer, err := newCluster(writeHost, port, password, false)
	if err != nil {
		reader.Close()
		return nil, fmt.Errorf("valkey writer: %w", err)
	}
	return &Client{reader: reader, writer: writer}, nil
}

// --- Read operations (use reader) ---

func (c *Client) Get(ctx context.Context, key string) (string, error) {
	return c.reader.Get(ctx, key).Result()
}

func (c *Client) Ping(ctx context.Context) error {
	return c.reader.Ping(ctx).Err()
}

// --- Write operations (use writer) ---

func (c *Client) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	return c.writer.Set(ctx, key, value, ttl).Err()
}

func (c *Client) Del(ctx context.Context, keys ...string) error {
	return c.writer.Del(ctx, keys...).Err()
}

func (c *Client) Incr(ctx context.Context, key string) (int64, error) {
	return c.writer.Incr(ctx, key).Result()
}

func (c *Client) Expire(ctx context.Context, key string, ttl time.Duration) error {
	return c.writer.Expire(ctx, key, ttl).Err()
}

func (c *Client) SetNX(ctx context.Context, key string, value interface{}, ttl time.Duration) (bool, error) {
	return c.writer.SetNX(ctx, key, value, ttl).Result()
}

func (c *Client) Eval(ctx context.Context, script string, keys []string, args ...interface{}) (interface{}, error) {
	return c.writer.Eval(ctx, script, keys, args...).Result()
}

// DelPattern deletes all keys matching a pattern using SCAN + DEL.
// Use sparingly — SCAN can be slow on large keyspaces.
func (c *Client) DelPattern(ctx context.Context, pattern string) error {
	var cursor uint64
	for {
		keys, next, err := c.writer.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return err
		}
		if len(keys) > 0 {
			c.writer.Del(ctx, keys...)
		}
		cursor = next
		if cursor == 0 {
			break
		}
	}
	return nil
}

func (c *Client) Close() error {
	var firstErr error
	if err := c.reader.Close(); err != nil {
		firstErr = err
	}
	if c.writer != c.reader {
		if err := c.writer.Close(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	return firstErr
}
