package consumer

import (
	"context"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.uber.org/zap"

	"github.com/multi-region-mall/search/internal/repository"
	"github.com/multi-region-mall/search/internal/service"
)

// ChangeStreamConsumer watches DocumentDB change streams for product changes
// and indexes them into OpenSearch. Used in SECONDARY regions where Kafka
// events aren't available (writes are forwarded to primary, and DocumentDB
// Global Cluster replicates the data).
type ChangeStreamConsumer struct {
	client  *mongo.Client
	service *service.SearchService
	logger  *zap.Logger
	dbName  string
}

type changeEvent struct {
	OperationType string `bson:"operationType"`
	FullDocument  bson.M `bson:"fullDocument"`
	DocumentKey   struct {
		ID interface{} `bson:"_id"`
	} `bson:"documentKey"`
}

func NewChangeStreamConsumer(mongoURI, dbName string, svc *service.SearchService, logger *zap.Logger) (*ChangeStreamConsumer, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(mongoURI))
	if err != nil {
		return nil, fmt.Errorf("connect to documentdb: %w", err)
	}

	if err := client.Ping(ctx, nil); err != nil {
		return nil, fmt.Errorf("ping documentdb: %w", err)
	}

	return &ChangeStreamConsumer{
		client:  client,
		service: svc,
		logger:  logger,
		dbName:  dbName,
	}, nil
}

func (c *ChangeStreamConsumer) Start(ctx context.Context) {
	go c.watch(ctx)
}

func (c *ChangeStreamConsumer) watch(ctx context.Context) {
	collection := c.client.Database(c.dbName).Collection("products")

	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.D{
			{Key: "operationType", Value: bson.D{
				{Key: "$in", Value: bson.A{"insert", "update", "replace", "delete"}},
			}},
		}}},
	}

	opts := options.ChangeStream().
		SetFullDocument(options.UpdateLookup).
		SetStartAtOperationTime(nil)

	c.logger.Info("starting DocumentDB change stream watcher",
		zap.String("database", c.dbName),
		zap.String("collection", "products"),
	)

	for {
		if ctx.Err() != nil {
			return
		}

		stream, err := collection.Watch(ctx, pipeline, opts)
		if err != nil {
			c.logger.Error("failed to open change stream, retrying in 5s", zap.Error(err))
			select {
			case <-ctx.Done():
				return
			case <-time.After(5 * time.Second):
				continue
			}
		}

		c.processStream(ctx, stream)
		stream.Close(ctx)

		// Brief pause before reconnecting
		select {
		case <-ctx.Done():
			return
		case <-time.After(1 * time.Second):
		}
	}
}

func (c *ChangeStreamConsumer) processStream(ctx context.Context, stream *mongo.ChangeStream) {
	for stream.Next(ctx) {
		var event changeEvent
		if err := stream.Decode(&event); err != nil {
			c.logger.Error("failed to decode change event", zap.Error(err))
			continue
		}

		switch event.OperationType {
		case "insert", "update", "replace":
			product, err := bsonToProduct(event.FullDocument)
			if err != nil {
				c.logger.Error("failed to convert document", zap.Error(err))
				continue
			}
			if err := c.service.IndexProduct(ctx, product); err != nil {
				c.logger.Error("failed to index product from change stream",
					zap.String("id", product.ID), zap.Error(err))
				continue
			}
			c.logger.Debug("indexed product from change stream",
				zap.String("id", product.ID), zap.String("op", event.OperationType))

		case "delete":
			id := fmt.Sprintf("%v", event.DocumentKey.ID)
			if err := c.service.DeleteProduct(ctx, id); err != nil {
				c.logger.Error("failed to delete product from change stream",
					zap.String("id", id), zap.Error(err))
				continue
			}
			c.logger.Debug("deleted product from change stream", zap.String("id", id))
		}
	}

	if err := stream.Err(); err != nil && ctx.Err() == nil {
		c.logger.Error("change stream error", zap.Error(err))
	}
}

func (c *ChangeStreamConsumer) Close() error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return c.client.Disconnect(ctx)
}

func bsonToProduct(doc bson.M) (repository.Product, error) {
	var p repository.Product
	p.ID = fmt.Sprintf("%v", doc["_id"])
	if v, ok := doc["name"].(string); ok {
		p.Name = v
	}
	if v, ok := doc["description"].(string); ok {
		p.Description = v
	}
	if v, ok := doc["sku"].(string); ok {
		p.SKU = v
	}
	if v, ok := doc["price"]; ok {
		switch val := v.(type) {
		case float64:
			p.Price = val
		case int32:
			p.Price = float64(val)
		case int64:
			p.Price = float64(val)
		}
	}
	if v, ok := doc["currency"].(string); ok {
		p.Currency = v
	}
	if v, ok := doc["category_id"].(string); ok {
		p.CategoryID = v
	}
	if v, ok := doc["is_active"].(bool); ok {
		p.IsActive = v
	}
	if v, ok := doc["images"].(bson.A); ok {
		for _, img := range v {
			if s, ok := img.(string); ok {
				p.Images = append(p.Images, s)
			}
		}
	}
	if v, ok := doc["attributes"].(bson.M); ok {
		p.Attributes = make(map[string]string)
		for k, val := range v {
			p.Attributes[k] = fmt.Sprintf("%v", val)
		}
	}
	return p, nil
}
