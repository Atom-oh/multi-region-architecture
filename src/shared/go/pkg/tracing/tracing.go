package tracing

import (
	"context"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/segmentio/kafka-go"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
	"go.opentelemetry.io/otel/trace"
	"go.uber.org/zap"
)

// InitTracer configures the OTEL trace provider with OTLP gRPC exporter.
func InitTracer(ctx context.Context, serviceName string) (*sdktrace.TracerProvider, error) {
	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String(serviceName),
			semconv.DeploymentEnvironmentKey.String(getEnv("DEPLOYMENT_ENV", "production")),
		),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.ParentBased(sdktrace.TraceIDRatioBased(1.0))),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp, nil
}

// GinMiddleware returns OTEL middleware for Gin.
func GinMiddleware(serviceName string) gin.HandlerFunc {
	return otelgin.Middleware(serviceName)
}

// HTTPClient returns an http.Client instrumented with OTEL.
func HTTPClient() *http.Client {
	return &http.Client{
		Transport: otelhttp.NewTransport(http.DefaultTransport),
	}
}

// TracedLogger wraps zap logger to include trace_id and span_id from context.
func TracedLogger(logger *zap.Logger, ctx context.Context) *zap.Logger {
	span := trace.SpanFromContext(ctx)
	if !span.SpanContext().IsValid() {
		return logger
	}
	return logger.With(
		zap.String("trace_id", span.SpanContext().TraceID().String()),
		zap.String("span_id", span.SpanContext().SpanID().String()),
	)
}

// KafkaCarrier implements TextMapCarrier for Kafka message headers.
type KafkaCarrier struct {
	Headers *[]kafka.Header
}

func NewKafkaCarrier(headers *[]kafka.Header) *KafkaCarrier {
	return &KafkaCarrier{Headers: headers}
}

func (c *KafkaCarrier) Get(key string) string {
	for _, h := range *c.Headers {
		if h.Key == key {
			return string(h.Value)
		}
	}
	return ""
}

func (c *KafkaCarrier) Set(key, value string) {
	for i, h := range *c.Headers {
		if h.Key == key {
			(*c.Headers)[i].Value = []byte(value)
			return
		}
	}
	*c.Headers = append(*c.Headers, kafka.Header{Key: key, Value: []byte(value)})
}

func (c *KafkaCarrier) Keys() []string {
	keys := make([]string, len(*c.Headers))
	for i, h := range *c.Headers {
		keys[i] = h.Key
	}
	return keys
}

// InjectKafkaHeaders injects trace context into Kafka message headers.
func InjectKafkaHeaders(ctx context.Context, headers *[]kafka.Header) {
	carrier := NewKafkaCarrier(headers)
	otel.GetTextMapPropagator().Inject(ctx, carrier)
}

// ExtractKafkaHeaders extracts trace context from Kafka message headers.
func ExtractKafkaHeaders(ctx context.Context, headers []kafka.Header) context.Context {
	carrier := NewKafkaCarrier(&headers)
	return otel.GetTextMapPropagator().Extract(ctx, carrier)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
