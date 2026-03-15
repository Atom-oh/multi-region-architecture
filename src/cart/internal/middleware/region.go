package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/shared/pkg/config"
	"github.com/multi-region-mall/shared/pkg/region"
)

func RegionWriteMiddleware(cfg *config.Config) gin.HandlerFunc {
	return region.WriteForwardMiddleware(cfg)
}
