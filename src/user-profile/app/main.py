"""User Profile Service - FastAPI application."""

import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import documentdb, health
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from app.config import config
from app.routers import profiles
from app.routers.health import router as health_router

logging.basicConfig(
    level=logging.INFO,
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"user-profile","logger":"%(name)s","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting user-profile service")

    await documentdb.connect(config.documentdb_uri, config.db_name)
    health.set_started(True)
    health.set_ready(True)
    logger.info("Connected to DocumentDB")

    yield

    logger.info("Shutting down user-profile service")
    health.set_ready(False)
    await documentdb.disconnect()


app = FastAPI(
    title="User Profile Service",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("user-profile", app)

app.add_middleware(RegionWriteMiddleware, config=config)

app.include_router(health_router)
app.include_router(profiles.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
