"""Review Service - FastAPI application."""

import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import documentdb, health
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from app.config import config
from app.routers import reviews
from app.routers.health import router as health_router
from app.services import review_service

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"review","logger":"%(name)s","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting review service")

    await documentdb.connect(config.documentdb_uri, config.db_name)
    logger.info("Connected to DocumentDB")

    await review_service.init_producer()
    logger.info("Connected to Kafka")

    health.set_started(True)
    health.set_ready(True)

    yield

    logger.info("Shutting down review service")
    health.set_ready(False)
    await review_service.stop_producer()
    await documentdb.disconnect()


app = FastAPI(
    title="Review Service",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("review", app)

app.add_middleware(RegionWriteMiddleware, config=config)

app.include_router(health_router)
app.include_router(reviews.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
