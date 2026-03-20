"""User Profile Service - FastAPI Application with stub responses."""

from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="user-profile")
app = FastAPI(title="User Profile Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock user profiles
MOCK_PROFILES = {
    "user-001": {
        "user_id": "user-001",
        "email": "john.doe@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "phone": "+1-555-123-4567",
        "address": {
            "street": "123 Main St",
            "city": "Seattle",
            "state": "WA",
            "zip": "98101",
            "country": "US",
        },
        "created_at": "2025-01-15T10:30:00Z",
        "preferences": {
            "language": "en",
            "currency": "USD",
            "notifications": {"email": True, "sms": False, "push": True},
        },
    },
    "user-002": {
        "user_id": "user-002",
        "email": "jane.smith@example.com",
        "first_name": "Jane",
        "last_name": "Smith",
        "phone": "+1-555-987-6543",
        "address": {
            "street": "456 Oak Ave",
            "city": "Portland",
            "state": "OR",
            "zip": "97201",
            "country": "US",
        },
        "created_at": "2025-02-20T14:45:00Z",
        "preferences": {
            "language": "en",
            "currency": "USD",
            "notifications": {"email": True, "sms": True, "push": False},
        },
    },
}


@app.get("/")
async def root():
    return {"service": "user-profile", "status": "running"}


@app.get("/api/v1/profiles/{user_id}")
async def get_profile(user_id: str):
    """Get user profile by ID."""
    if user_id in MOCK_PROFILES:
        return MOCK_PROFILES[user_id]
    raise HTTPException(status_code=404, detail="Profile not found")


@app.put("/api/v1/profiles/{user_id}")
async def update_profile(user_id: str, profile: dict):
    """Update user profile (stub - returns merged data)."""
    base = MOCK_PROFILES.get(user_id, {"user_id": user_id})
    return {
        **base,
        **profile,
        "user_id": user_id,
        "updated": True,
    }


@app.get("/api/v1/profiles/{user_id}/preferences")
async def get_preferences(user_id: str):
    """Get user preferences."""
    if user_id in MOCK_PROFILES:
        return {
            "user_id": user_id,
            "preferences": MOCK_PROFILES[user_id]["preferences"],
        }
    raise HTTPException(status_code=404, detail="Profile not found")


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
