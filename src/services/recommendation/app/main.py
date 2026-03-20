"""Recommendation Service - FastAPI Application with stub responses."""

from fastapi import FastAPI
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="recommendation")
app = FastAPI(title="Recommendation Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock recommendations
MOCK_USER_RECOMMENDATIONS = {
    "user-001": [
        {"product_id": "prod-002", "name": "Running Shoes", "price": 129.99, "score": 0.95, "reason": "Based on your fitness purchases"},
        {"product_id": "prod-005", "name": "Yoga Mat", "price": 29.99, "score": 0.88, "reason": "Frequently bought together"},
        {"product_id": "prod-004", "name": "Laptop Stand", "price": 39.99, "score": 0.82, "reason": "Popular in your area"},
    ],
    "user-002": [
        {"product_id": "prod-001", "name": "Wireless Headphones", "price": 79.99, "score": 0.92, "reason": "Based on your browsing history"},
        {"product_id": "prod-003", "name": "Coffee Maker", "price": 49.99, "score": 0.85, "reason": "Trending this week"},
    ],
}

MOCK_TRENDING = [
    {"product_id": "prod-001", "name": "Wireless Headphones", "price": 79.99, "trend_score": 0.98, "sales_increase": "45%"},
    {"product_id": "prod-002", "name": "Running Shoes", "price": 129.99, "trend_score": 0.94, "sales_increase": "32%"},
    {"product_id": "prod-003", "name": "Coffee Maker", "price": 49.99, "trend_score": 0.89, "sales_increase": "28%"},
    {"product_id": "prod-004", "name": "Laptop Stand", "price": 39.99, "trend_score": 0.85, "sales_increase": "22%"},
    {"product_id": "prod-005", "name": "Yoga Mat", "price": 29.99, "trend_score": 0.81, "sales_increase": "18%"},
]

MOCK_SIMILAR = {
    "prod-001": [
        {"product_id": "prod-006", "name": "Bluetooth Earbuds", "price": 59.99, "similarity": 0.92},
        {"product_id": "prod-007", "name": "Noise Cancelling Headphones Pro", "price": 149.99, "similarity": 0.88},
    ],
    "prod-002": [
        {"product_id": "prod-008", "name": "Trail Running Shoes", "price": 139.99, "similarity": 0.95},
        {"product_id": "prod-009", "name": "Athletic Socks Pack", "price": 19.99, "similarity": 0.72},
    ],
}


@app.get("/")
async def root():
    return {"service": "recommendation", "status": "running"}


@app.get("/api/v1/recommendations/{user_id}")
async def get_user_recommendations(user_id: str, limit: int = 10):
    """Get personalized recommendations for a user."""
    recommendations = MOCK_USER_RECOMMENDATIONS.get(user_id, MOCK_TRENDING[:3])
    return {
        "user_id": user_id,
        "recommendations": recommendations[:limit],
        "total": len(recommendations),
    }


@app.get("/api/v1/recommendations/trending")
async def get_trending(limit: int = 10, category: str = None):
    """Get trending products."""
    products = MOCK_TRENDING
    return {
        "trending": products[:limit],
        "total": len(products),
        "category": category,
    }


@app.get("/api/v1/recommendations/similar/{product_id}")
async def get_similar_products(product_id: str, limit: int = 5):
    """Get similar products."""
    similar = MOCK_SIMILAR.get(product_id, [])
    return {
        "product_id": product_id,
        "similar_products": similar[:limit],
        "total": len(similar),
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
