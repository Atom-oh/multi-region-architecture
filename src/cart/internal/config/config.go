package config

import (
	sharedconfig "github.com/multi-region-mall/shared/pkg/config"
)

func Load() *sharedconfig.Config {
	return sharedconfig.Load("cart")
}
