"""Notification Service - FastAPI Application."""

import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.documentdb import connect, disconnect
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

from app.routers.notifications import router as notifications_router
from app.config import config

logger = logging.getLogger(__name__)
app = FastAPI(redirect_slashes=False, title="Notification Service", version="1.0.0")

# Event consumers - initialized on startup
_event_consumers = None

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_tracing(config.service_name, app)
app.include_router(health_router)
app.include_router(notifications_router)


@app.get("/")
async def root():
    return {"service": "notification", "status": "running"}


@app.on_event("startup")
async def startup():
    global _event_consumers

    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            logger.info("Connected to DocumentDB")
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, using fallback mock data")

    # Initialize Kafka consumers for event processing (graceful degradation)
    if config.kafka_brokers and config.kafka_brokers != "localhost:9092":
        try:
            from app.consumers.event_consumers import event_consumers
            await event_consumers.start()
            _event_consumers = event_consumers
            logger.info(f"Kafka consumers started for brokers: {config.kafka_brokers}")
        except Exception as e:
            logger.warning(f"Kafka unavailable: {e}, event consumers disabled")
    else:
        logger.info(f"No MSK brokers configured (KAFKA_BROKERS={config.kafka_brokers}), event consumers disabled")

    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _event_consumers

    await disconnect()

    if _event_consumers:
        try:
            await _event_consumers.stop()
            logger.info("Kafka consumers stopped")
        except Exception as e:
            logger.warning(f"Error stopping Kafka consumers: {e}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
