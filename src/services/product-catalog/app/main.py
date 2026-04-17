"""Product Catalog Service - FastAPI Application."""

import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.documentdb import connect, connect_writer, disconnect
from mall_common import valkey
from mall_common.kafka import Producer
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

from app.routers.products import router as products_router
from app.services import product_service

logger = logging.getLogger(__name__)
config = ServiceConfig(service_name="product-catalog")
app = FastAPI(redirect_slashes=False, title="Product Catalog Service", version="1.0.0")

# Kafka producer for catalog events - initialized on startup
_kafka_producer: Producer | None = None

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
app.include_router(products_router)


@app.get("/")
async def root():
    return {"service": "product-catalog", "status": "running"}


@app.on_event("startup")
async def startup():
    global _kafka_producer

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

    # Initialize Kafka producer for catalog events (graceful degradation)
    if config.kafka_brokers and config.kafka_brokers != "localhost:9092":
        try:
            _kafka_producer = Producer(brokers=config.kafka_brokers)
            await _kafka_producer.start()
            product_service.set_producer(_kafka_producer)
            logger.info(f"Kafka producer initialized for brokers: {config.kafka_brokers}")
        except Exception as e:
            logger.warning(f"Kafka unavailable: {e}, catalog events disabled")
            _kafka_producer = None
    else:
        logger.info(f"No MSK brokers configured (KAFKA_BROKERS={config.kafka_brokers}), catalog events disabled")

    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _kafka_producer

    await disconnect()
    await valkey.disconnect()

    if _kafka_producer:
        try:
            await _kafka_producer.stop()
            logger.info("Kafka producer stopped")
        except Exception as e:
            logger.warning(f"Error stopping Kafka producer: {e}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
