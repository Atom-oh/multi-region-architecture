"""Notification service main application."""

import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common.tracing import init_tracing, TraceLogFilter

from app.config import config
from app.consumers.event_consumers import event_consumers
from app.routers import health, notifications

logging.basicConfig(
    level=getattr(logging, config.log_level.upper()),
    format='{"timestamp":"%(asctime)s","level":"%(levelname)s","service":"notification","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s","logger":"%(name)s"}',
    handlers=[logging.StreamHandler(sys.stdout)],
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting notification service")

    await event_consumers.start()
    logger.info("Started Kafka consumers")

    health.set_started(True)
    health.set_ready(True)
    logger.info("Notification service ready")

    yield

    logger.info("Shutting down notification service")
    health.set_ready(False)

    await event_consumers.stop()

    logger.info("Notification service shutdown complete")


app = FastAPI(
    title="Notification Service",
    description="Multi-channel notification dispatch",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("notification", app)

app.include_router(health.router)
app.include_router(notifications.router)


def handle_sigterm(*args):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
