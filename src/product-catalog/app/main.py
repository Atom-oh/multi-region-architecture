"""Product Catalog Service - FastAPI Application."""

import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import documentdb, valkey
from mall_common.kafka import Producer
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from app.config import config
from app.routers import health, products
from app.services import product_service

logging.basicConfig(
    level=getattr(logging, config.log_level.upper()),
    format='{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)

_producer: Producer | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _producer
    logger.info("Starting %s service", config.service_name)

    # Connect to DocumentDB
    await documentdb.connect(config.documentdb_uri, config.db_name)
    logger.info("Connected to DocumentDB")

    # Connect to Valkey
    await valkey.connect(config.cache_host, config.cache_port)
    logger.info("Connected to Valkey")

    # Initialize Kafka producer
    _producer = Producer(config.kafka_brokers)
    await _producer.start()
    product_service.set_producer(_producer)
    logger.info("Kafka producer started")

    # Set health status
    health.set_started(True)
    health.set_ready(True)

    yield

    # Cleanup
    logger.info("Shutting down %s service", config.service_name)
    health.set_ready(False)

    if _producer:
        await _producer.stop()
    await valkey.disconnect()
    await documentdb.disconnect()

    logger.info("Shutdown complete")


app = FastAPI(
    title="Product Catalog Service",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("product-catalog", app)

# Add region write middleware
app.add_middleware(RegionWriteMiddleware, config=config)

# Include routers
app.include_router(health.router)
app.include_router(products.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
