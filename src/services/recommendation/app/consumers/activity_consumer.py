"""Kafka consumer for user activity events."""

import asyncio
import logging
from datetime import datetime

from mall_common.kafka import Consumer

from app.config import config
from app.repositories.recommendation_repo import recommendation_repo

logger = logging.getLogger(__name__)


async def handle_activity_event(key: str, value: dict) -> None:
    """Handle user activity events from Kafka."""
    try:
        activity = {
            "user_id": value.get("user_id"),
            "product_id": value.get("product_id"),
            "action": value.get("action", "view"),
            "timestamp": datetime.fromisoformat(value.get("timestamp", datetime.utcnow().isoformat())),
            "metadata": value.get("metadata", {}),
        }

        await recommendation_repo.save_activity(activity)
        logger.debug("Processed activity event for user %s", activity["user_id"])
    except Exception:
        logger.exception("Failed to process activity event: %s", value)


class ActivityConsumer:
    def __init__(self):
        self._consumer: Consumer | None = None
        self._task: asyncio.Task | None = None

    async def start(self) -> None:
        self._consumer = Consumer(
            brokers=config.kafka_brokers,
            topic="user.activity",
            group_id="recommendation-activity-consumer",
            handler=handle_activity_event,
        )
        await self._consumer.start()
        self._task = asyncio.create_task(self._consumer.consume())
        logger.info("Activity consumer started")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

        if self._consumer:
            await self._consumer.stop()

        logger.info("Activity consumer stopped")


activity_consumer = ActivityConsumer()
