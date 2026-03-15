"""Multi-topic Kafka consumers for notification events."""

import asyncio
import logging

from mall_common.kafka import Consumer

from app.config import config
from app.services.notification_service import notification_service

logger = logging.getLogger(__name__)


async def handle_order_event(key: str, value: dict) -> None:
    """Handle order events."""
    logger.debug("Received order event: %s", value.get("type"))
    await notification_service.process_order_event(value)


async def handle_payment_event(key: str, value: dict) -> None:
    """Handle payment events."""
    logger.debug("Received payment event: %s", value.get("type"))
    await notification_service.process_payment_event(value)


async def handle_shipping_event(key: str, value: dict) -> None:
    """Handle shipping events."""
    logger.debug("Received shipping event: %s", value.get("type"))
    await notification_service.process_shipping_event(value)


class EventConsumers:
    def __init__(self):
        self._consumers: list[Consumer] = []
        self._tasks: list[asyncio.Task] = []

    async def start(self) -> None:
        """Start all event consumers."""
        consumer_configs = [
            ("orders.*", "notification-orders-consumer", handle_order_event),
            ("payments.*", "notification-payments-consumer", handle_payment_event),
            ("shipping.*", "notification-shipping-consumer", handle_shipping_event),
        ]

        for topic, group_id, handler in consumer_configs:
            consumer = Consumer(
                brokers=config.kafka_brokers,
                topic=topic,
                group_id=group_id,
                handler=handler,
            )
            await consumer.start()
            task = asyncio.create_task(consumer.consume())
            self._consumers.append(consumer)
            self._tasks.append(task)
            logger.info("Started consumer for topic: %s", topic)

        logger.info("All event consumers started")

    async def stop(self) -> None:
        """Stop all event consumers."""
        for task in self._tasks:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass

        for consumer in self._consumers:
            await consumer.stop()

        self._consumers.clear()
        self._tasks.clear()
        logger.info("All event consumers stopped")


event_consumers = EventConsumers()
