"""Review Service - FastAPI Application."""

import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.documentdb import connect, disconnect
from mall_common import valkey
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

from app.routers.reviews import router as reviews_router

logger = logging.getLogger(__name__)
config = ServiceConfig(service_name="review")
app = FastAPI(redirect_slashes=False, title="Review Service", version="1.0.0")

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
app.include_router(reviews_router)


@app.get("/")
async def root():
    return {"service": "review", "status": "running"}


@app.on_event("startup")
async def startup():
    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            logger.info("Connected to DocumentDB")
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, using fallback mock data")
    if config.cache_host != "localhost":
        try:
            await valkey.connect(config.cache_host, config.cache_port)
            logger.info("Connected to Valkey")
        except Exception as e:
            logger.warning(f"Valkey unavailable: {e}, review caching disabled")
    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    await disconnect()
    await valkey.disconnect()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
