package config

import (
	"os"
	"strconv"

	sharedconfig "github.com/multi-region-mall/shared/pkg/config"
)

type Config struct {
	*sharedconfig.Config
	RateLimitRPS    int
	RateLimitBurst  int
	RateLimitWindow int // seconds
}

func Load() *Config {
	base := sharedconfig.Load("api-gateway")
	return &Config{
		Config:          base,
		RateLimitRPS:    getEnvInt("RATE_LIMIT_RPS", 100),
		RateLimitBurst:  getEnvInt("RATE_LIMIT_BURST", 200),
		RateLimitWindow: getEnvInt("RATE_LIMIT_WINDOW", 60),
	}
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}
