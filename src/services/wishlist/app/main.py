"""Wishlist Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="wishlist")
app = FastAPI(title="Wishlist Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock wishlists
MOCK_WISHLISTS = {
    "user-001": {
        "user_id": "user-001",
        "items": [
            {"item_id": "item-001", "product_id": "prod-001", "name": "Wireless Headphones", "price": 79.99, "added_at": "2026-03-15T10:00:00Z"},
            {"item_id": "item-002", "product_id": "prod-003", "name": "Coffee Maker", "price": 49.99, "added_at": "2026-03-16T14:30:00Z"},
        ],
        "created_at": "2026-03-15T10:00:00Z",
        "updated_at": "2026-03-16T14:30:00Z",
    },
    "user-002": {
        "user_id": "user-002",
        "items": [
            {"item_id": "item-003", "product_id": "prod-002", "name": "Running Shoes", "price": 129.99, "added_at": "2026-03-18T09:15:00Z"},
        ],
        "created_at": "2026-03-18T09:15:00Z",
        "updated_at": "2026-03-18T09:15:00Z",
    },
}


@app.get("/")
async def root():
    return {"service": "wishlist", "status": "running"}


@app.get("/api/v1/wishlists/{user_id}")
async def get_wishlist(user_id: str):
    """Get user's wishlist."""
    if user_id in MOCK_WISHLISTS:
        return MOCK_WISHLISTS[user_id]
    return {
        "user_id": user_id,
        "items": [],
        "created_at": datetime.utcnow().isoformat(),
        "updated_at": datetime.utcnow().isoformat(),
    }


@app.post("/api/v1/wishlists/{user_id}/items")
async def add_item(user_id: str, item: dict):
    """Add item to wishlist (stub - returns acknowledgment)."""
    return {
        "user_id": user_id,
        "item_id": f"item-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "product_id": item.get("product_id", "unknown"),
        "name": item.get("name", "Unknown Product"),
        "price": item.get("price", 0.0),
        "added_at": datetime.utcnow().isoformat(),
        "added": True,
    }


@app.delete("/api/v1/wishlists/{user_id}/items/{item_id}")
async def remove_item(user_id: str, item_id: str):
    """Remove item from wishlist (stub - returns acknowledgment)."""
    return {
        "user_id": user_id,
        "item_id": item_id,
        "removed": True,
        "removed_at": datetime.utcnow().isoformat(),
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
