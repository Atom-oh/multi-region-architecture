"""Wishlist models."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class WishlistItem(BaseModel):
    product_id: str
    name: Optional[str] = None
    price: Optional[int] = None
    original_price: Optional[int] = None
    image_url: Optional[str] = None
    in_stock: Optional[bool] = None
    price_dropped: bool = False
    added_at: datetime = Field(default_factory=datetime.utcnow)
    note: Optional[str] = None


class Wishlist(BaseModel):
    user_id: str
    items: list[WishlistItem] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class WishlistItemCreate(BaseModel):
    product_id: str
    note: Optional[str] = None
