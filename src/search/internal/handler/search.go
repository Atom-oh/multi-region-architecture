package handler

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/search/internal/repository"
	"github.com/multi-region-mall/search/internal/service"
)

type SearchHandler struct {
	service *service.SearchService
}

func NewSearchHandler(service *service.SearchService) *SearchHandler {
	return &SearchHandler{service: service}
}

func (h *SearchHandler) RegisterRoutes(r *gin.Engine) {
	api := r.Group("/api/v1")
	api.GET("/search", h.Search)
}

func (h *SearchHandler) Search(c *gin.Context) {
	params := repository.SearchParams{
		Query:    c.Query("q"),
		Category: c.Query("category"),
		Page:     1,
		Size:     20,
	}

	if page, err := strconv.Atoi(c.Query("page")); err == nil && page > 0 {
		params.Page = page
	}
	if size, err := strconv.Atoi(c.Query("size")); err == nil && size > 0 && size <= 100 {
		params.Size = size
	}
	if minPrice, err := strconv.ParseFloat(c.Query("min_price"), 64); err == nil {
		params.MinPrice = &minPrice
	}
	if maxPrice, err := strconv.ParseFloat(c.Query("max_price"), 64); err == nil {
		params.MaxPrice = &maxPrice
	}

	result, err := h.service.Search(c.Request.Context(), params)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, result)
}
