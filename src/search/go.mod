module github.com/multi-region-mall/search

go 1.22

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/multi-region-mall/shared v0.0.0
	github.com/opensearch-project/opensearch-go/v2 v2.3.0
	github.com/redis/go-redis/v9 v9.4.0
	github.com/segmentio/kafka-go v0.4.47
	go.uber.org/zap v1.27.0
	go.opentelemetry.io/otel v1.28.0
	go.opentelemetry.io/otel/trace v1.28.0
	go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.53.0
)

replace github.com/multi-region-mall/shared => ../shared/go
