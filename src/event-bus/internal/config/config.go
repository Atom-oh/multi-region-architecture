package config

import (
	sharedconfig "github.com/multi-region-mall/shared/pkg/config"
)

type Config struct {
	*sharedconfig.Config
}

func Load() *Config {
	base := sharedconfig.Load("event-bus")
	return &Config{
		Config: base,
	}
}
