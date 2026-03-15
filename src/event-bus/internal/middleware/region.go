package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/multi-region-mall/event-bus/internal/config"
	"github.com/multi-region-mall/shared/pkg/region"
	sharedconfig "github.com/multi-region-mall/shared/pkg/config"
)

func RegionForward(cfg *config.Config) gin.HandlerFunc {
	sharedCfg := &sharedconfig.Config{
		RegionRole:  cfg.RegionRole,
		PrimaryHost: cfg.PrimaryHost,
		AWSRegion:   cfg.AWSRegion,
	}
	return region.WriteForwardMiddleware(sharedCfg)
}
