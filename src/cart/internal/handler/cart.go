package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/cart/internal/model"
	"github.com/multi-region-mall/cart/internal/service"
)

type CartHandler struct {
	service *service.CartService
}

func NewCartHandler(service *service.CartService) *CartHandler {
	return &CartHandler{service: service}
}

func (h *CartHandler) RegisterRoutes(r *gin.Engine) {
	api := r.Group("/api/v1/cart")
	api.GET("/:user_id", h.GetCart)
	api.POST("/:user_id/items", h.AddItem)
	api.PUT("/:user_id/items/:item_id", h.UpdateItem)
	api.DELETE("/:user_id/items/:item_id", h.RemoveItem)
	api.DELETE("/:user_id", h.ClearCart)
}

func (h *CartHandler) GetCart(c *gin.Context) {
	userID := c.Param("user_id")

	cart, err := h.service.GetCart(c.Request.Context(), userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, cart)
}

func (h *CartHandler) AddItem(c *gin.Context) {
	userID := c.Param("user_id")

	var req model.AddItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item, err := h.service.AddItem(c.Request.Context(), userID, req)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, item)
}

func (h *CartHandler) UpdateItem(c *gin.Context) {
	userID := c.Param("user_id")
	itemID := c.Param("item_id")

	var req model.UpdateItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	item, err := h.service.UpdateItem(c.Request.Context(), userID, itemID, req.Quantity)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	if item == nil && req.Quantity == 0 {
		c.Status(http.StatusNoContent)
		return
	}

	if item == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
		return
	}

	c.JSON(http.StatusOK, item)
}

func (h *CartHandler) RemoveItem(c *gin.Context) {
	userID := c.Param("user_id")
	itemID := c.Param("item_id")

	if err := h.service.RemoveItem(c.Request.Context(), userID, itemID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.Status(http.StatusNoContent)
}

func (h *CartHandler) ClearCart(c *gin.Context) {
	userID := c.Param("user_id")

	if err := h.service.ClearCart(c.Request.Context(), userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.Status(http.StatusNoContent)
}
