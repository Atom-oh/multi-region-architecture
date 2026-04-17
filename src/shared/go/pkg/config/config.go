package config

import (
	"os"
	"strconv"
)

type Config struct {
	ServiceName    string
	Port           string
	AWSRegion      string
	RegionRole     string // PRIMARY or SECONDARY
	PrimaryHost    string
	DBHost         string
	DBPort         int
	DBName         string
	DBUser         string
	DBPassword     string
	CacheHost      string
	CacheWriteHost string // Writer endpoint for cache writes (GDS primary)
	CachePort      int
	CachePassword  string
	KafkaBrokers   string
	OpenSearchURL  string
	DocumentDBHost   string
	DocumentDBPort   int
	LogLevel         string
	DBWriteHost      string // Writer endpoint for writes
	DBReadHostLocal  string // AZ-local reader endpoint for reads
	KafkaBrokersLocal string // AZ-local Kafka brokers
	ClientRack       string // Kafka client.rack for rack-aware consumption
	PreferReplicaAZ  string // ElastiCache AZ-local replica preference
	AvailabilityZone string // Current AZ
}

func Load(serviceName string) *Config {
	return &Config{
		ServiceName:    serviceName,
		Port:           getEnv("PORT", "8080"),
		AWSRegion:      getEnv("AWS_REGION", "us-east-1"),
		RegionRole:     getEnv("REGION_ROLE", "PRIMARY"),
		PrimaryHost:    getEnv("PRIMARY_HOST", ""),
		DBHost:         getEnv("DB_HOST", "localhost"),
		DBPort:         getEnvInt("DB_PORT", 5432),
		DBName:         getEnv("DB_NAME", serviceName),
		DBUser:         getEnv("DB_USER", "mall"),
		DBPassword:     getEnv("DB_PASSWORD", ""),
		CacheHost:      getEnv("CACHE_HOST", "localhost"),
		CacheWriteHost: getEnv("CACHE_WRITE_HOST", ""),
		CachePort:      getEnvInt("CACHE_PORT", 6379),
		CachePassword:  getEnv("CACHE_AUTH_TOKEN", ""),
		KafkaBrokers:   getEnv("KAFKA_BROKERS", "localhost:9092"),
		OpenSearchURL:  getEnv("OPENSEARCH_ENDPOINT", "http://localhost:9200"),
		DocumentDBHost: getEnv("DOCUMENTDB_HOST", "localhost"),
		DocumentDBPort: getEnvInt("DOCUMENTDB_PORT", 27017),
		LogLevel:         getEnv("LOG_LEVEL", "info"),
		DBWriteHost:      getEnv("DB_WRITE_HOST", ""),
		DBReadHostLocal:  getEnv("DB_READ_HOST_LOCAL", ""),
		KafkaBrokersLocal: getEnv("KAFKA_BROKERS_LOCAL", ""),
		ClientRack:       getEnv("CLIENT_RACK", ""),
		PreferReplicaAZ:  getEnv("PREFER_REPLICA_AZ", ""),
		AvailabilityZone: getEnv("AVAILABILITY_ZONE", ""),
	}
}

func (c *Config) IsPrimary() bool {
	return c.RegionRole == "PRIMARY"
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}
