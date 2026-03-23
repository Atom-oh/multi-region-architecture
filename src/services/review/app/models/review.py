"""Review models."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, field_validator


class Review(BaseModel):
    id: str = ""
    user_id: str
    user_name: str = ""
    product_id: str
    rating: int = Field(..., ge=1, le=5)
    title: str
    body: str
    helpful_count: int = 0
    verified_purchase: bool = False
    product_name: Optional[str] = None
    product_image_url: Optional[str] = None
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ReviewCreate(BaseModel):
    user_id: str
    product_id: str
    rating: int = Field(..., ge=1, le=5)
    title: str = Field(..., min_length=1, max_length=200)
    body: str = Field(..., min_length=1, max_length=5000)
    verified_purchase: bool = False

    @field_validator("rating")
    @classmethod
    def validate_rating(cls, v: int) -> int:
        if v < 1 or v > 5:
            raise ValueError("Rating must be between 1 and 5")
        return v


class ReviewUpdate(BaseModel):
    rating: Optional[int] = Field(None, ge=1, le=5)
    title: Optional[str] = Field(None, min_length=1, max_length=200)
    body: Optional[str] = Field(None, min_length=1, max_length=5000)


class ReviewListResponse(BaseModel):
    reviews: list[Review]
    total: int
    page: int
    page_size: int
    has_more: bool
