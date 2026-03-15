"""OpenTelemetry tracing initialization for Python microservices."""

import logging
import os

from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.instrumentation.pymongo import PymongoInstrumentor
from opentelemetry.propagate import inject, extract
from opentelemetry.propagators.textmap import DefaultGetter
from opentelemetry.sdk.resources import Resource, SERVICE_NAME
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

logger = logging.getLogger(__name__)


def init_tracing(service_name: str, app=None):
    """Initialize OpenTelemetry tracing with OTLP gRPC exporter.

    Args:
        service_name: Name of the microservice.
        app: FastAPI application instance to instrument.
    """
    endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317")

    resource = Resource.create({
        SERVICE_NAME: service_name,
        "deployment.environment": os.getenv("DEPLOYMENT_ENV", "production"),
    })

    exporter = OTLPSpanExporter(endpoint=endpoint, insecure=True)
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(BatchSpanProcessor(exporter))
    trace.set_tracer_provider(provider)

    # Auto-instrument libraries
    if app is not None:
        FastAPIInstrumentor.instrument_app(app)
    HTTPXClientInstrumentor().instrument()
    RedisInstrumentor().instrument()
    PymongoInstrumentor().instrument()

    logger.info("OpenTelemetry tracing initialized for %s -> %s", service_name, endpoint)
    return provider


class KafkaTraceInjector:
    """Inject trace context into Kafka message headers."""

    @staticmethod
    def inject_headers(headers: list[tuple[str, bytes]] | None = None) -> list[tuple[str, bytes]]:
        if headers is None:
            headers = []
        carrier = {}
        inject(carrier)
        for key, value in carrier.items():
            headers.append((key, value.encode("utf-8")))
        return headers


class KafkaTraceExtractor:
    """Extract trace context from Kafka message headers."""

    @staticmethod
    def extract_context(headers: list[tuple[str, bytes]] | None = None):
        if not headers:
            return trace.set_span_in_context(trace.INVALID_SPAN)
        carrier = {}
        for key, value in headers:
            if isinstance(value, bytes):
                carrier[key] = value.decode("utf-8")
            else:
                carrier[key] = value
        return extract(carrier)


class TraceLogFilter(logging.Filter):
    """Logging filter that adds trace_id and span_id to log records."""

    def filter(self, record):
        span = trace.get_current_span()
        if span and span.get_span_context().is_valid:
            ctx = span.get_span_context()
            record.trace_id = format(ctx.trace_id, "032x")
            record.span_id = format(ctx.span_id, "016x")
        else:
            record.trace_id = ""
            record.span_id = ""
        return True
