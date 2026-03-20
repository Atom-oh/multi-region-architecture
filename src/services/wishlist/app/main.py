"""Wishlist Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="wishlist")
app = FastAPI(title="Wishlist Service", version="1.0.0")

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

# Mock wishlists - consistent with shared IDs
MOCK_WISHLISTS = {
    "USR-001": {
        "user_id": "USR-001",
        "items": [
            {
                "item_id": "wish-001",
                "product_id": "PRD-003",
                "name": "다이슨 에어랩",
                "price": 699000,
                "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap",
                "added_at": "2026-03-15T10:00:00Z",
                "in_stock": True,
                "price_dropped": False,
            },
            {
                "item_id": "wish-002",
                "product_id": "PRD-007",
                "name": "LG 올레드 TV 65\"",
                "price": 3290000,
                "image_url": "https://placehold.co/400x400/EEE/333?text=LG+OLED+65",
                "added_at": "2026-03-16T14:30:00Z",
                "in_stock": True,
                "price_dropped": True,
                "original_price": 3590000,
            },
        ],
        "item_count": 2,
        "created_at": "2026-03-15T10:00:00Z",
        "updated_at": "2026-03-16T14:30:00Z",
    },
    "USR-002": {
        "user_id": "USR-002",
        "items": [
            {
                "item_id": "wish-003",
                "product_id": "PRD-004",
                "name": "애플 맥북 프로 M4",
                "price": 2990000,
                "image_url": "https://placehold.co/400x400/EEE/333?text=MacBook+M4",
                "added_at": "2026-03-18T09:15:00Z",
                "in_stock": True,
                "price_dropped": False,
            },
            {
                "item_id": "wish-004",
                "product_id": "PRD-001",
                "name": "삼성 갤럭시 S25 울트라",
                "price": 1890000,
                "image_url": "https://placehold.co/400x400/EEE/333?text=Galaxy+S25",
                "added_at": "2026-03-19T11:20:00Z",
                "in_stock": True,
                "price_dropped": False,
            },
        ],
        "item_count": 2,
        "created_at": "2026-03-18T09:15:00Z",
        "updated_at": "2026-03-19T11:20:00Z",
    },
    "USR-003": {
        "user_id": "USR-003",
        "items": [
            {
                "item_id": "wish-005",
                "product_id": "PRD-006",
                "name": "아디다스 울트라부스트",
                "price": 219000,
                "image_url": "https://placehold.co/400x400/EEE/333?text=Ultraboost",
                "added_at": "2026-03-17T16:45:00Z",
                "in_stock": True,
                "price_dropped": True,
                "original_price": 239000,
            },
        ],
        "item_count": 1,
        "created_at": "2026-03-17T16:45:00Z",
        "updated_at": "2026-03-17T16:45:00Z",
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
        "item_count": 0,
        "created_at": datetime.utcnow().isoformat(),
        "updated_at": datetime.utcnow().isoformat(),
    }


@app.post("/api/v1/wishlists/{user_id}/items")
async def add_item(user_id: str, item: dict):
    """Add item to wishlist (stub - returns acknowledgment)."""
    return {
        "user_id": user_id,
        "item_id": f"wish-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "product_id": item.get("product_id", "unknown"),
        "name": item.get("name", "상품명"),
        "price": item.get("price", 0),
        "added_at": datetime.utcnow().isoformat(),
        "added": True,
        "message": "위시리스트에 추가되었습니다",
    }


@app.delete("/api/v1/wishlists/{user_id}/items/{item_id}")
async def remove_item(user_id: str, item_id: str):
    """Remove item from wishlist (stub - returns acknowledgment)."""
    return {
        "user_id": user_id,
        "item_id": item_id,
        "removed": True,
        "removed_at": datetime.utcnow().isoformat(),
        "message": "위시리스트에서 삭제되었습니다",
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
