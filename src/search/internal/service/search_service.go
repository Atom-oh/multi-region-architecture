package service

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/multi-region-mall/search/internal/repository"
	"github.com/multi-region-mall/shared/pkg/valkey"
)

const cacheTTL = 5 * time.Minute

type SearchService struct {
	repo  *repository.OpenSearchRepo
	cache *valkey.Client
}

func NewSearchService(repo *repository.OpenSearchRepo, cache *valkey.Client) *SearchService {
	return &SearchService{repo: repo, cache: cache}
}

func (s *SearchService) Search(ctx context.Context, params repository.SearchParams) (*repository.SearchResult, error) {
	cacheKey := s.buildCacheKey(params)

	// Try cache first
	if cached, err := s.cache.Get(ctx, cacheKey); err == nil && cached != "" {
		var result repository.SearchResult
		if err := json.Unmarshal([]byte(cached), &result); err == nil {
			return &result, nil
		}
	}

	// Search in OpenSearch
	result, err := s.repo.SearchProducts(ctx, params)
	if err != nil {
		return nil, err
	}

	// Cache result
	if data, err := json.Marshal(result); err == nil {
		_ = s.cache.Set(ctx, cacheKey, string(data), cacheTTL)
	}

	return result, nil
}

func (s *SearchService) IndexProduct(ctx context.Context, product repository.Product) error {
	return s.repo.IndexProduct(ctx, product)
}

func (s *SearchService) DeleteProduct(ctx context.Context, productID string) error {
	return s.repo.DeleteProduct(ctx, productID)
}

func (s *SearchService) buildCacheKey(params repository.SearchParams) string {
	key := fmt.Sprintf("search:%s:%s:%d:%d", params.Query, params.Category, params.Page, params.Size)
	if params.MinPrice != nil {
		key += fmt.Sprintf(":min%.2f", *params.MinPrice)
	}
	if params.MaxPrice != nil {
		key += fmt.Sprintf(":max%.2f", *params.MaxPrice)
	}
	return key
}
