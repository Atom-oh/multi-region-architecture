"""Pydantic models for recommendation service."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class Recommendation(BaseModel):
    product_id: str
    score: float = Field(ge=0.0, le=1.0)
    reason: str
    category: Optional[str] = None


class UserActivity(BaseModel):
    user_id: str
    product_id: str
    action: str  # view, click, purchase, add_to_cart
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    metadata: Optional[dict] = None


class TrendingProduct(BaseModel):
    product_id: str
    name: str
    category: str
    score: float
    view_count: int
    purchase_count: int


class RecommendationResponse(BaseModel):
    user_id: str
    recommendations: list[Recommendation]
    generated_at: datetime = Field(default_factory=datetime.utcnow)


class TrendingResponse(BaseModel):
    products: list[TrendingProduct]
    generated_at: datetime = Field(default_factory=datetime.utcnow)


class SimilarProductsResponse(BaseModel):
    product_id: str
    similar: list[Recommendation]
    generated_at: datetime = Field(default_factory=datetime.utcnow)
