"""User Profile Service - FastAPI Application with stub responses."""

import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.documentdb import connect, connect_writer, disconnect, get_db, get_write_db
from mall_common import valkey
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

logger = logging.getLogger(__name__)
config = ServiceConfig(service_name="user-profile")
app = FastAPI(redirect_slashes=False, title="User Profile Service", version="1.0.0")
_db_connected = False

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


@app.get("/")
async def root():
    return {"service": "user-profile", "status": "running"}


@app.get("/api/v1/profiles")
async def list_profiles(limit: int = 50):
    """List all user profiles."""
    if _db_connected:
        try:
            db = get_db()
            cursor = db["user_profiles"].find().limit(limit)
            profiles = []
            async for doc in cursor:
                doc["_id"] = str(doc["_id"])
                profiles.append(doc)
            return {"profiles": profiles, "total": len(profiles)}
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}")
    return {"profiles": [], "total": 0}


@app.get("/api/v1/profiles/{user_id}")
async def get_profile(user_id: str):
    """Get user profile by ID."""
    if _db_connected:
        try:
            db = get_db()
            doc = await db["user_profiles"].find_one({"userId": user_id})
            if doc:
                doc["_id"] = str(doc["_id"])
                return doc
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}")
    raise HTTPException(status_code=404, detail="프로필을 찾을 수 없습니다")


@app.put("/api/v1/profiles/{user_id}")
async def update_profile(user_id: str, profile: dict):
    """Update user profile."""
    if _db_connected:
        try:
            db = get_write_db()
            result = await db["user_profiles"].update_one(
                {"userId": user_id}, {"$set": profile}
            )
            if result.matched_count > 0:
                return {"user_id": user_id, "updated": True, "message": "프로필이 업데이트되었습니다"}
        except Exception as e:
            logger.warning(f"DocumentDB update failed: {e}")
    return {"user_id": user_id, "updated": False, "message": "프로필을 찾을 수 없습니다"}


@app.get("/api/v1/profiles/{user_id}/preferences")
async def get_preferences(user_id: str):
    """Get user preferences."""
    if _db_connected:
        try:
            db = get_db()
            doc = await db["user_profiles"].find_one({"userId": user_id}, {"preferences": 1})
            if doc:
                return {"user_id": user_id, "preferences": doc.get("preferences", {})}
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}")
    raise HTTPException(status_code=404, detail="프로필을 찾을 수 없습니다")


@app.on_event("startup")
async def startup():
    global _db_connected
    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            _db_connected = True
            logger.info("Connected to DocumentDB (read)")
            if config.documentdb_write_host:
                await connect_writer(config.documentdb_write_uri, config.db_name or "mall")
                logger.info("Connected to DocumentDB writer at %s", config.documentdb_write_host)
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}")
    if config.cache_host != "localhost":
        try:
            await valkey.connect(config.cache_host, config.cache_port)
            logger.info("Connected to Valkey")
        except Exception as e:
            logger.warning(f"Valkey unavailable: {e}, profile caching disabled")
    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    await disconnect()
    await valkey.disconnect()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
