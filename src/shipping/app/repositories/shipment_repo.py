"""Shipment repository for DocumentDB operations."""

import logging
from datetime import datetime
from typing import Optional
from bson import ObjectId

from mall_common.documentdb import get_db
from ..models.shipment import Shipment, ShipmentCreate, ShipmentStatus, TrackingEvent

logger = logging.getLogger(__name__)

COLLECTION = "shipments"


def _doc_to_shipment(doc: dict) -> Shipment:
    doc["id"] = str(doc.pop("_id"))
    return Shipment(**doc)


async def create(data: ShipmentCreate) -> Shipment:
    db = get_db()
    now = datetime.utcnow()
    doc = {
        "order_id": data.order_id,
        "user_id": data.user_id,
        "shipping_address": data.shipping_address,
        "carrier": data.carrier,
        "tracking_number": None,
        "status": ShipmentStatus.PENDING.value,
        "tracking_history": [
            {
                "status": ShipmentStatus.PENDING.value,
                "location": None,
                "description": "Shipment created",
                "timestamp": now,
            }
        ],
        "created_at": now,
        "updated_at": now,
    }
    result = await db[COLLECTION].insert_one(doc)
    doc["_id"] = result.inserted_id
    logger.info("Created shipment for order %s", data.order_id)
    return _doc_to_shipment(doc)


async def get_by_id(shipment_id: str) -> Optional[Shipment]:
    db = get_db()
    doc = await db[COLLECTION].find_one({"_id": ObjectId(shipment_id)})
    if doc:
        return _doc_to_shipment(doc)
    return None


async def get_by_order_id(order_id: str) -> Optional[Shipment]:
    db = get_db()
    doc = await db[COLLECTION].find_one({"order_id": order_id})
    if doc:
        return _doc_to_shipment(doc)
    return None


async def update_status(
    shipment_id: str, status: ShipmentStatus, location: Optional[str] = None, description: Optional[str] = None
) -> Optional[Shipment]:
    db = get_db()
    now = datetime.utcnow()
    event = TrackingEvent(
        status=status,
        location=location,
        description=description or f"Status changed to {status.value}",
        timestamp=now,
    )
    result = await db[COLLECTION].find_one_and_update(
        {"_id": ObjectId(shipment_id)},
        {
            "$set": {"status": status.value, "updated_at": now},
            "$push": {"tracking_history": event.model_dump()},
        },
        return_document=True,
    )
    if result:
        logger.info("Updated shipment %s status to %s", shipment_id, status.value)
        return _doc_to_shipment(result)
    return None


async def set_tracking_number(shipment_id: str, tracking_number: str, carrier: str) -> Optional[Shipment]:
    db = get_db()
    result = await db[COLLECTION].find_one_and_update(
        {"_id": ObjectId(shipment_id)},
        {
            "$set": {
                "tracking_number": tracking_number,
                "carrier": carrier,
                "updated_at": datetime.utcnow(),
            }
        },
        return_document=True,
    )
    if result:
        return _doc_to_shipment(result)
    return None
