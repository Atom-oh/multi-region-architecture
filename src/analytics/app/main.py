"""Analytics service main application."""

import asyncio
import logging
import signal
import sys
from contextlib import asynccontextmanager

from fastapi import FastAPI

from mall_common import health
from mall_common.region import RegionWriteMiddleware
from mall_common.tracing import init_tracing, TraceLogFilter

from .config import settings
from .routers import analytics
from .routers import health as health_router
from .consumers.all_events_consumer import EventConsumer
from .services.analytics_service import analytics_service

logging.basicConfig(
    level=getattr(logging, settings.log_level.upper()),
    format='{"time":"%(asctime)s","level":"%(levelname)s","trace_id":"%(trace_id)s","span_id":"%(span_id)s","message":"%(message)s"}',
    stream=sys.stdout,
)
logging.getLogger().addFilter(TraceLogFilter())
logger = logging.getLogger(__name__)

consumer_task = None
event_consumer = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global consumer_task, event_consumer

    logger.info(
        "Starting analytics service",
        extra={"region": settings.aws_region, "role": settings.region_role},
    )

    # Initialize event consumer
    event_consumer = EventConsumer(settings, analytics_service)
    await event_consumer.start()

    # Start consuming events in background
    consumer_task = asyncio.create_task(event_consumer.consume())

    health.set_started(True)
    health.set_ready(True)

    yield

    logger.info("Shutting down analytics service")
    health.set_ready(False)

    # Stop consumer
    if consumer_task:
        consumer_task.cancel()
        try:
            await consumer_task
        except asyncio.CancelledError:
            pass

    if event_consumer:
        await event_consumer.stop()

    # Flush remaining events to S3
    await analytics_service.flush_to_s3()

    logger.info("Analytics service stopped")


app = FastAPI(
    title="Analytics Service",
    description="Event aggregation and analytics for the multi-region shopping mall",
    version="1.0.0",
    lifespan=lifespan,
)

init_tracing("analytics", app)

app.add_middleware(RegionWriteMiddleware, config=settings)

app.include_router(health_router.router)
app.include_router(analytics.router)


def handle_sigterm(signum, frame):
    logger.info("Received SIGTERM, initiating graceful shutdown")
    sys.exit(0)


signal.signal(signal.SIGTERM, handle_sigterm)
