"""Shipment service with cache-aside pattern."""

import logging
from typing import Optional

from mall_common import valkey
from ..models.shipment import Shipment, ShipmentCreate, ShipmentStatus, TrackingEvent
from ..repositories import shipment_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 300  # 5 minutes


def _cache_key(shipment_id: str) -> str:
    return f"shipment:{shipment_id}"


def _order_cache_key(order_id: str) -> str:
    return f"shipment:order:{order_id}"


async def create_shipment(data: ShipmentCreate) -> Shipment:
    shipment = await shipment_repo.create(data)
    await valkey.set_json(_cache_key(shipment.id), shipment.model_dump(mode="json"), CACHE_TTL)
    await valkey.set_json(_order_cache_key(shipment.order_id), shipment.model_dump(mode="json"), CACHE_TTL)
    return shipment


async def get_shipment(shipment_id: str) -> Optional[Shipment]:
    cached = await valkey.get_json(_cache_key(shipment_id))
    if cached:
        return Shipment(**cached)

    shipment = await shipment_repo.get_by_id(shipment_id)
    if shipment:
        await valkey.set_json(_cache_key(shipment_id), shipment.model_dump(mode="json"), CACHE_TTL)
    return shipment


async def get_shipment_by_order(order_id: str) -> Optional[Shipment]:
    cached = await valkey.get_json(_order_cache_key(order_id))
    if cached:
        return Shipment(**cached)

    shipment = await shipment_repo.get_by_order_id(order_id)
    if shipment:
        await valkey.set_json(_order_cache_key(order_id), shipment.model_dump(mode="json"), CACHE_TTL)
        await valkey.set_json(_cache_key(shipment.id), shipment.model_dump(mode="json"), CACHE_TTL)
    return shipment


async def update_tracking_status(
    shipment_id: str, status: ShipmentStatus, location: Optional[str] = None, description: Optional[str] = None
) -> Optional[Shipment]:
    shipment = await shipment_repo.update_status(shipment_id, status, location, description)
    if shipment:
        await valkey.delete(_cache_key(shipment_id))
        await valkey.delete(_order_cache_key(shipment.order_id))
    return shipment


async def get_tracking_history(shipment_id: str) -> list[TrackingEvent]:
    shipment = await get_shipment(shipment_id)
    if shipment:
        return shipment.tracking_history
    return []


async def create_from_order_event(order_data: dict) -> Shipment:
    """Create shipment from Kafka order.confirmed event."""
    data = ShipmentCreate(
        order_id=order_data.get("order_id") or order_data.get("id"),
        user_id=order_data.get("user_id"),
        shipping_address=order_data.get("shipping_address", ""),
    )
    logger.info("Creating shipment from order event: %s", data.order_id)
    return await create_shipment(data)
