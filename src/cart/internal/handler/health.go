package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/health"
)

type HealthHandler struct {
	checker *health.Checker
}

func NewHealthHandler(checker *health.Checker) *HealthHandler {
	return &HealthHandler{checker: checker}
}

func (h *HealthHandler) RegisterRoutes(r *gin.Engine) {
	h.checker.RegisterRoutes(r)
}
