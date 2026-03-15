"""Recommendation service main application."""

import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import documentdb, valkey
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from app.config import config
from app.consumers.activity_consumer import activity_consumer
from app.routers import health, recommendations

logging.basicConfig(
    level=getattr(logging, config.log_level.upper()),
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"recommendation","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s","logger":"%(name)s"}',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting recommendation service")

    await documentdb.connect(config.documentdb_uri, config.db_name)
    logger.info("Connected to DocumentDB")

    await valkey.connect(config.cache_host, config.cache_port)
    logger.info("Connected to Valkey")

    await activity_consumer.start()
    logger.info("Started Kafka consumer")

    health.set_started(True)
    health.set_ready(True)
    logger.info("Recommendation service ready")

    yield

    logger.info("Shutting down recommendation service")
    health.set_ready(False)

    await activity_consumer.stop()
    await valkey.disconnect()
    await documentdb.disconnect()

    logger.info("Recommendation service shutdown complete")


app = FastAPI(
    title="Recommendation Service",
    description="Personalized product recommendations",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("recommendation", app)

app.add_middleware(RegionWriteMiddleware, config=config)

app.include_router(health.router)
app.include_router(recommendations.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
