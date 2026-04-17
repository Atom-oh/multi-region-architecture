"""Recommendation Service - FastAPI Application."""

import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.documentdb import connect, connect_writer, disconnect
from mall_common import valkey
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

from app.routers.recommendations import router as recommendations_router
from app.config import config

logger = logging.getLogger(__name__)
app = FastAPI(redirect_slashes=False, title="Recommendation Service", version="1.0.0")

# Kafka consumer for user activity events - initialized on startup
_activity_consumer = None

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
app.include_router(recommendations_router)


@app.get("/")
async def root():
    return {"service": "recommendation", "status": "running"}


@app.on_event("startup")
async def startup():
    global _activity_consumer

    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            logger.info("Connected to DocumentDB (read)")
            if config.documentdb_write_host:
                await connect_writer(config.documentdb_write_uri, config.db_name or "mall")
                logger.info("Connected to DocumentDB writer at %s", config.documentdb_write_host)
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, using fallback mock data")
    if config.cache_host != "localhost":
        try:
            await valkey.connect(config.cache_host, config.cache_port)
            logger.info("Connected to Valkey")
        except Exception as e:
            logger.warning(f"Valkey unavailable: {e}")

    # Initialize Kafka consumer for user activity events (graceful degradation)
    if config.kafka_brokers and config.kafka_brokers != "localhost:9092":
        try:
            from app.consumers.activity_consumer import activity_consumer
            await activity_consumer.start()
            _activity_consumer = activity_consumer
            logger.info(f"Activity consumer started for brokers: {config.kafka_brokers}")
        except Exception as e:
            logger.warning(f"Kafka unavailable: {e}, activity consumer disabled")
    else:
        logger.info(f"No MSK brokers configured (KAFKA_BROKERS={config.kafka_brokers}), activity consumer disabled")

    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _activity_consumer

    await disconnect()
    await valkey.disconnect()

    if _activity_consumer:
        try:
            await _activity_consumer.stop()
            logger.info("Activity consumer stopped")
        except Exception as e:
            logger.warning(f"Error stopping activity consumer: {e}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
