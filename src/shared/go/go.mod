module github.com/multi-region-mall/shared

go 1.22

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/opensearch-project/opensearch-go/v2 v2.3.0
	github.com/jackc/pgx/v5 v5.5.0
	github.com/redis/go-redis/v9 v9.4.0
	github.com/segmentio/kafka-go v0.4.47
	go.uber.org/zap v1.27.0
	go.opentelemetry.io/otel v1.28.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.28.0
	go.opentelemetry.io/otel/sdk v1.28.0
	go.opentelemetry.io/otel/trace v1.28.0
	go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.53.0
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.53.0
)
