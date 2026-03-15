package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/health"
)

func RegisterHealthRoutes(r *gin.Engine, checker *health.Checker) {
	checker.RegisterRoutes(r)
}
