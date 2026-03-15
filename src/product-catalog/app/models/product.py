"""Product and Category Pydantic models."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class CategoryBase(BaseModel):
    name: str
    description: Optional[str] = None
    parent_id: Optional[str] = None


class Category(CategoryBase):
    id: str = Field(alias="_id")
    created_at: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        populate_by_name = True


class ProductBase(BaseModel):
    name: str
    description: Optional[str] = None
    sku: str
    price: float
    currency: str = "USD"
    category_id: Optional[str] = None
    images: list[str] = Field(default_factory=list)
    attributes: dict = Field(default_factory=dict)
    inventory_count: int = 0
    is_active: bool = True


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    price: Optional[float] = None
    currency: Optional[str] = None
    category_id: Optional[str] = None
    images: Optional[list[str]] = None
    attributes: Optional[dict] = None
    inventory_count: Optional[int] = None
    is_active: Optional[bool] = None


class Product(ProductBase):
    id: str = Field(alias="_id")
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        populate_by_name = True
