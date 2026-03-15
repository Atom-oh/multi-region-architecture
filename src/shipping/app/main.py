"""Shipping service main application."""

import asyncio
import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import documentdb, valkey
from mall_common.health import set_ready, set_started
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from .config import config
from .consumers.order_consumer import create_consumer
from .routers import health, shipments

logging.basicConfig(
    level=getattr(logging, config.log_level.upper()),
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"%(name)s","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    stream=sys.stdout,
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(config.service_name)

consumer_task: asyncio.Task | None = None


async def run_consumer():
    consumer = create_consumer(config.kafka_brokers)
    await consumer.start()
    try:
        await consumer.consume()
    finally:
        await consumer.stop()


@asynccontextmanager
async def lifespan(app: FastAPI):
    global consumer_task
    logger.info("Starting %s service", config.service_name)

    # Connect to DocumentDB
    await documentdb.connect(config.documentdb_uri, config.db_name)
    logger.info("Connected to DocumentDB")

    # Connect to Valkey
    await valkey.connect(config.cache_host, config.cache_port)
    logger.info("Connected to Valkey")

    # Start Kafka consumer in background
    consumer_task = asyncio.create_task(run_consumer())
    logger.info("Started Kafka consumer")

    set_started(True)
    set_ready(True)
    logger.info("Service ready")

    yield

    logger.info("Shutting down %s service", config.service_name)
    set_ready(False)

    if consumer_task:
        consumer_task.cancel()
        try:
            await consumer_task
        except asyncio.CancelledError:
            pass

    await valkey.disconnect()
    await documentdb.disconnect()
    logger.info("Shutdown complete")


app = FastAPI(
    title="Shipping Service",
    description="Shipping and tracking management for multi-region shopping mall",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("shipping", app)

app.add_middleware(RegionWriteMiddleware, config=config)
app.include_router(health.router)
app.include_router(shipments.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
