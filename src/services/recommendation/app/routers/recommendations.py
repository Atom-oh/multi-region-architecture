"""Recommendation API routes."""

from fastapi import APIRouter

from app.models.recommendation import RecommendationResponse, SimilarProductsResponse, TrendingResponse
from app.services.recommendation_service import recommendation_service

router = APIRouter(prefix="/api/v1/recommendations", tags=["recommendations"])


@router.get("/{user_id}", response_model=RecommendationResponse)
async def get_recommendations(user_id: str, limit: int = 10):
    """Get personalized recommendations for a user."""
    return await recommendation_service.get_personalized_recommendations(user_id, limit)


@router.get("/trending", response_model=TrendingResponse)
async def get_trending():
    """Get trending products."""
    return await recommendation_service.get_trending_products()


@router.get("/similar/{product_id}", response_model=SimilarProductsResponse)
async def get_similar_products(product_id: str, limit: int = 10):
    """Get similar products based on user behavior."""
    return await recommendation_service.get_similar_products(product_id, limit)
