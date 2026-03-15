package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/multi-region-mall/inventory/internal/model"
	"github.com/multi-region-mall/inventory/internal/repository"
	"github.com/multi-region-mall/inventory/internal/service"
)

type InventoryHandler struct {
	service *service.InventoryService
}

func NewInventoryHandler(service *service.InventoryService) *InventoryHandler {
	return &InventoryHandler{service: service}
}

func (h *InventoryHandler) RegisterRoutes(r *gin.Engine) {
	api := r.Group("/api/v1/inventory")
	api.GET("/:sku", h.GetStock)
	api.POST("/:sku/reserve", h.Reserve)
	api.POST("/:sku/release", h.Release)
	api.PUT("/:sku", h.UpdateStock)
}

func (h *InventoryHandler) GetStock(c *gin.Context) {
	sku := c.Param("sku")

	inv, err := h.service.GetStock(c.Request.Context(), sku)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "inventory not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, inv)
}

func (h *InventoryHandler) Reserve(c *gin.Context) {
	sku := c.Param("sku")

	var req model.ReserveRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	inv, err := h.service.Reserve(c.Request.Context(), sku, req.Quantity)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "inventory not found"})
		return
	}
	if errors.Is(err, repository.ErrInsufficientStock) {
		c.JSON(http.StatusConflict, gin.H{"error": "insufficient stock"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, inv)
}

func (h *InventoryHandler) Release(c *gin.Context) {
	sku := c.Param("sku")

	var req model.ReleaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	inv, err := h.service.Release(c.Request.Context(), sku, req.Quantity)
	if errors.Is(err, repository.ErrNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "inventory not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, inv)
}

func (h *InventoryHandler) UpdateStock(c *gin.Context) {
	sku := c.Param("sku")

	var req model.UpdateStockRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	inv, err := h.service.UpdateStock(c.Request.Context(), sku, req.Available, req.Total)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, inv)
}
