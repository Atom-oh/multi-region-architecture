package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/api-gateway/internal/config"
	"github.com/multi-region-mall/shared/pkg/region"
	sharedconfig "github.com/multi-region-mall/shared/pkg/config"
)

func RegionForward(cfg *config.Config) gin.HandlerFunc {
	// Convert to shared config for the region middleware
	sharedCfg := &sharedconfig.Config{
		RegionRole:  cfg.RegionRole,
		PrimaryHost: cfg.PrimaryHost,
		AWSRegion:   cfg.AWSRegion,
	}
	return region.WriteForwardMiddleware(sharedCfg)
}
