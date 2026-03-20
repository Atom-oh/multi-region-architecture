"""Kafka consumer for order events."""

import logging
from typing import Any

from mall_common.kafka import Consumer
from ..services import shipment_service

logger = logging.getLogger(__name__)


async def handle_order_confirmed(key: str, value: Any) -> None:
    """Handle orders.confirmed event by creating a shipment."""
    logger.info("Received order.confirmed event: key=%s", key)
    try:
        await shipment_service.create_from_order_event(value)
    except Exception:
        logger.exception("Failed to create shipment from order event")


def create_consumer(brokers: str) -> Consumer:
    return Consumer(
        brokers=brokers,
        topic="orders.confirmed",
        group_id="shipping-service",
        handler=handle_order_confirmed,
    )
