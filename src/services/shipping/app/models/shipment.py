"""Shipment models."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class ShipmentStatus(str, Enum):
    PENDING = "PENDING"
    PICKED_UP = "PICKED_UP"
    IN_TRANSIT = "IN_TRANSIT"
    OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"
    DELIVERED = "DELIVERED"


class TrackingEvent(BaseModel):
    status: ShipmentStatus
    location: Optional[str] = None
    description: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class ShipmentCreate(BaseModel):
    order_id: str
    user_id: str
    shipping_address: str
    carrier: Optional[str] = None


class Shipment(BaseModel):
    id: Optional[str] = None
    order_id: str
    user_id: str
    shipping_address: str
    carrier: Optional[str] = None
    tracking_number: Optional[str] = None
    status: ShipmentStatus = ShipmentStatus.PENDING
    tracking_history: list[TrackingEvent] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    class Config:
        from_attributes = True
