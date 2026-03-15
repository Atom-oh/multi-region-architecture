package repository

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/opensearch-project/opensearch-go/v2"
	"github.com/opensearch-project/opensearch-go/v2/opensearchapi"
)

const indexName = "products"

type OpenSearchRepo struct {
	client *opensearch.Client
}

type Product struct {
	ID          string            `json:"id"`
	Name        string            `json:"name"`
	Description string            `json:"description"`
	SKU         string            `json:"sku"`
	Price       float64           `json:"price"`
	Currency    string            `json:"currency"`
	CategoryID  string            `json:"category_id"`
	Images      []string          `json:"images"`
	Attributes  map[string]string `json:"attributes"`
	IsActive    bool              `json:"is_active"`
}

type SearchParams struct {
	Query    string
	Category string
	MinPrice *float64
	MaxPrice *float64
	Page     int
	Size     int
}

type SearchResult struct {
	Products []Product `json:"products"`
	Total    int64     `json:"total"`
	Page     int       `json:"page"`
	Size     int       `json:"size"`
}

func NewOpenSearchRepo(endpoint string) (*OpenSearchRepo, error) {
	client, err := opensearch.NewClient(opensearch.Config{
		Addresses: []string{endpoint},
	})
	if err != nil {
		return nil, fmt.Errorf("opensearch client: %w", err)
	}

	return &OpenSearchRepo{client: client}, nil
}

func (r *OpenSearchRepo) EnsureIndex(ctx context.Context) error {
	exists, err := r.client.Indices.Exists([]string{indexName})
	if err != nil {
		return fmt.Errorf("check index exists: %w", err)
	}
	defer exists.Body.Close()

	if exists.StatusCode == 200 {
		return nil
	}

	mapping := `{
		"mappings": {
			"properties": {
				"id": {"type": "keyword"},
				"name": {"type": "text", "analyzer": "standard"},
				"description": {"type": "text", "analyzer": "standard"},
				"sku": {"type": "keyword"},
				"price": {"type": "float"},
				"currency": {"type": "keyword"},
				"category_id": {"type": "keyword"},
				"is_active": {"type": "boolean"}
			}
		}
	}`

	res, err := r.client.Indices.Create(indexName, r.client.Indices.Create.WithBody(strings.NewReader(mapping)))
	if err != nil {
		return fmt.Errorf("create index: %w", err)
	}
	defer res.Body.Close()

	return nil
}

func (r *OpenSearchRepo) IndexProduct(ctx context.Context, product Product) error {
	data, err := json.Marshal(product)
	if err != nil {
		return fmt.Errorf("marshal product: %w", err)
	}

	req := opensearchapi.IndexRequest{
		Index:      indexName,
		DocumentID: product.ID,
		Body:       bytes.NewReader(data),
		Refresh:    "true",
	}

	res, err := req.Do(ctx, r.client)
	if err != nil {
		return fmt.Errorf("index product: %w", err)
	}
	defer res.Body.Close()

	if res.IsError() {
		return fmt.Errorf("index product error: %s", res.String())
	}

	return nil
}

func (r *OpenSearchRepo) SearchProducts(ctx context.Context, params SearchParams) (*SearchResult, error) {
	must := []map[string]interface{}{}
	filter := []map[string]interface{}{}

	if params.Query != "" {
		must = append(must, map[string]interface{}{
			"multi_match": map[string]interface{}{
				"query":  params.Query,
				"fields": []string{"name^2", "description", "sku"},
			},
		})
	}

	if params.Category != "" {
		filter = append(filter, map[string]interface{}{
			"term": map[string]interface{}{"category_id": params.Category},
		})
	}

	if params.MinPrice != nil || params.MaxPrice != nil {
		priceRange := map[string]interface{}{}
		if params.MinPrice != nil {
			priceRange["gte"] = *params.MinPrice
		}
		if params.MaxPrice != nil {
			priceRange["lte"] = *params.MaxPrice
		}
		filter = append(filter, map[string]interface{}{
			"range": map[string]interface{}{"price": priceRange},
		})
	}

	filter = append(filter, map[string]interface{}{
		"term": map[string]interface{}{"is_active": true},
	})

	query := map[string]interface{}{
		"query": map[string]interface{}{
			"bool": map[string]interface{}{
				"must":   must,
				"filter": filter,
			},
		},
		"from": (params.Page - 1) * params.Size,
		"size": params.Size,
	}

	if len(must) == 0 {
		query["query"] = map[string]interface{}{
			"bool": map[string]interface{}{
				"filter": filter,
			},
		}
	}

	data, _ := json.Marshal(query)
	res, err := r.client.Search(
		r.client.Search.WithContext(ctx),
		r.client.Search.WithIndex(indexName),
		r.client.Search.WithBody(bytes.NewReader(data)),
	)
	if err != nil {
		return nil, fmt.Errorf("search: %w", err)
	}
	defer res.Body.Close()

	if res.IsError() {
		return nil, fmt.Errorf("search error: %s", res.String())
	}

	var result struct {
		Hits struct {
			Total struct {
				Value int64 `json:"value"`
			} `json:"total"`
			Hits []struct {
				Source Product `json:"_source"`
			} `json:"hits"`
		} `json:"hits"`
	}

	if err := json.NewDecoder(res.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	products := make([]Product, len(result.Hits.Hits))
	for i, hit := range result.Hits.Hits {
		products[i] = hit.Source
	}

	return &SearchResult{
		Products: products,
		Total:    result.Hits.Total.Value,
		Page:     params.Page,
		Size:     params.Size,
	}, nil
}

func (r *OpenSearchRepo) DeleteProduct(ctx context.Context, productID string) error {
	req := opensearchapi.DeleteRequest{
		Index:      indexName,
		DocumentID: productID,
		Refresh:    "true",
	}

	res, err := req.Do(ctx, r.client)
	if err != nil {
		return fmt.Errorf("delete product: %w", err)
	}
	defer res.Body.Close()

	return nil
}

func (r *OpenSearchRepo) Ping(ctx context.Context) error {
	res, err := r.client.Ping()
	if err != nil {
		return err
	}
	defer res.Body.Close()
	return nil
}
