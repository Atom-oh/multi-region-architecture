"""Profile models."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class Address(BaseModel):
    id: str = Field(default_factory=lambda: "")
    label: str = Field(..., description="Label for this address (e.g., Home, Work)")
    street: str
    city: str
    state: str
    postal_code: str
    country: str = "US"
    is_default: bool = False


class UserProfile(BaseModel):
    user_id: str
    phone: Optional[str] = None
    date_of_birth: Optional[str] = None
    avatar_url: Optional[str] = None
    preferences: dict = Field(default_factory=dict)
    addresses: list[Address] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ProfileUpdate(BaseModel):
    phone: Optional[str] = None
    date_of_birth: Optional[str] = None
    avatar_url: Optional[str] = None
    preferences: Optional[dict] = None


class AddressCreate(BaseModel):
    label: str
    street: str
    city: str
    state: str
    postal_code: str
    country: str = "US"
    is_default: bool = False


class AddressUpdate(BaseModel):
    label: Optional[str] = None
    street: Optional[str] = None
    city: Optional[str] = None
    state: Optional[str] = None
    postal_code: Optional[str] = None
    country: Optional[str] = None
    is_default: Optional[bool] = None
