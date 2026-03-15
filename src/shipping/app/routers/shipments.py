"""Shipments API router."""

from typing import Optional

from fastapi import APIRouter, HTTPException

from ..models.shipment import Shipment, ShipmentCreate, ShipmentStatus, TrackingEvent
from ..services import shipment_service

router = APIRouter(prefix="/api/v1/shipments", tags=["shipments"])


@router.get("/{order_id}", response_model=Shipment)
async def get_shipment_by_order(order_id: str):
    """Get shipment by order ID."""
    shipment = await shipment_service.get_shipment_by_order(order_id)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return shipment


@router.post("", response_model=Shipment, status_code=201)
async def create_shipment(data: ShipmentCreate):
    """Create a new shipment."""
    return await shipment_service.create_shipment(data)


class StatusUpdate(ShipmentCreate):
    status: ShipmentStatus
    location: Optional[str] = None
    description: Optional[str] = None

    class Config:
        extra = "forbid"


from pydantic import BaseModel


class StatusUpdateRequest(BaseModel):
    status: ShipmentStatus
    location: Optional[str] = None
    description: Optional[str] = None


@router.put("/{shipment_id}/status", response_model=Shipment)
async def update_shipment_status(shipment_id: str, update: StatusUpdateRequest):
    """Update shipment tracking status."""
    shipment = await shipment_service.update_tracking_status(
        shipment_id, update.status, update.location, update.description
    )
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return shipment


@router.get("/{shipment_id}/tracking", response_model=list[TrackingEvent])
async def get_tracking_history(shipment_id: str):
    """Get shipment tracking history."""
    history = await shipment_service.get_tracking_history(shipment_id)
    if not history:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return history
