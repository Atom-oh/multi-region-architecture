"""Review Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="review")
app = FastAPI(title="Review Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock reviews
MOCK_REVIEWS = [
    {
        "review_id": "rev-001",
        "product_id": "prod-001",
        "user_id": "user-001",
        "rating": 5,
        "title": "Excellent headphones!",
        "content": "Great sound quality and comfortable to wear for long periods.",
        "verified_purchase": True,
        "helpful_votes": 42,
        "created_at": "2026-03-10T15:30:00Z",
    },
    {
        "review_id": "rev-002",
        "product_id": "prod-001",
        "user_id": "user-002",
        "rating": 4,
        "title": "Good but pricey",
        "content": "Sound is great, noise cancellation works well. A bit expensive though.",
        "verified_purchase": True,
        "helpful_votes": 18,
        "created_at": "2026-03-12T09:45:00Z",
    },
    {
        "review_id": "rev-003",
        "product_id": "prod-002",
        "user_id": "user-001",
        "rating": 5,
        "title": "Perfect running shoes",
        "content": "Very lightweight and comfortable. My marathon times have improved!",
        "verified_purchase": True,
        "helpful_votes": 67,
        "created_at": "2026-03-14T20:15:00Z",
    },
]


@app.get("/")
async def root():
    return {"service": "review", "status": "running"}


@app.get("/api/v1/reviews/product/{product_id}")
async def get_product_reviews(product_id: str, limit: int = 10, offset: int = 0):
    """Get reviews for a product."""
    reviews = [r for r in MOCK_REVIEWS if r["product_id"] == product_id]
    avg_rating = sum(r["rating"] for r in reviews) / len(reviews) if reviews else 0
    return {
        "product_id": product_id,
        "reviews": reviews[offset:offset + limit],
        "total": len(reviews),
        "average_rating": round(avg_rating, 1),
        "limit": limit,
        "offset": offset,
    }


@app.post("/api/v1/reviews")
async def create_review(review: dict):
    """Create a new review (stub - returns mock response)."""
    return {
        "review_id": f"rev-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "product_id": review.get("product_id", "unknown"),
        "user_id": review.get("user_id", "unknown"),
        "rating": review.get("rating", 5),
        "title": review.get("title", ""),
        "content": review.get("content", ""),
        "verified_purchase": False,
        "helpful_votes": 0,
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
    }


@app.get("/api/v1/reviews/{review_id}")
async def get_review(review_id: str):
    """Get a single review by ID."""
    for review in MOCK_REVIEWS:
        if review["review_id"] == review_id:
            return review
    raise HTTPException(status_code=404, detail="Review not found")


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
