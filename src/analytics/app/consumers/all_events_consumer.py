"""Consumer for all event topics."""

import asyncio
import logging
from datetime import datetime
from typing import Any
from uuid import uuid4

from aiokafka import AIOKafkaConsumer

from ..config import AnalyticsConfig
from ..models.analytics import EventRecord
from ..services.analytics_service import AnalyticsService

logger = logging.getLogger(__name__)

TOPICS = [
    "orders",
    "payments",
    "inventory",
    "users",
    "products",
    "cart",
    "shipping",
    "notifications",
    "reviews",
    "pricing",
    "analytics",
    "recommendations",
]


class EventConsumer:
    def __init__(self, config: AnalyticsConfig, analytics_service: AnalyticsService):
        self.config = config
        self.analytics_service = analytics_service
        self.consumer: AIOKafkaConsumer | None = None
        self._running = False

        # Initialize S3 if configured
        if config.s3_bucket:
            analytics_service.initialize_s3(config.s3_bucket, config.s3_prefix)

    async def start(self) -> None:
        """Start the Kafka consumer."""
        self.consumer = AIOKafkaConsumer(
            *TOPICS,
            bootstrap_servers=self.config.kafka_brokers,
            group_id=f"analytics-{self.config.aws_region}",
            auto_offset_reset="earliest",
            enable_auto_commit=True,
        )
        await self.consumer.start()
        self._running = True
        logger.info(f"Started consuming from topics: {TOPICS}")

        # Start periodic flush task
        asyncio.create_task(self._periodic_flush())

    async def stop(self) -> None:
        """Stop the Kafka consumer."""
        self._running = False
        if self.consumer:
            await self.consumer.stop()
            logger.info("Consumer stopped")

    async def consume(self) -> None:
        """Consume messages from all topics."""
        if not self.consumer:
            logger.error("Consumer not started")
            return

        try:
            async for msg in self.consumer:
                if not self._running:
                    break

                try:
                    await self._handle_message(msg)
                except Exception as e:
                    logger.error(f"Failed to handle message: {e}")
        except asyncio.CancelledError:
            logger.info("Consumer task cancelled")

    async def _handle_message(self, msg: Any) -> None:
        """Handle a single message."""
        import json

        try:
            payload = json.loads(msg.value.decode("utf-8")) if msg.value else {}
        except json.JSONDecodeError:
            payload = {"raw": msg.value.decode("utf-8") if msg.value else ""}

        key = msg.key.decode("utf-8") if msg.key else None

        event = EventRecord(
            id=str(uuid4()),
            topic=msg.topic,
            key=key,
            payload=payload,
            timestamp=datetime.utcnow(),
            region=self.config.aws_region,
        )

        await self.analytics_service.record_event(event)

    async def _periodic_flush(self) -> None:
        """Periodically flush events to S3."""
        while self._running:
            await asyncio.sleep(self.config.flush_interval_seconds)
            try:
                await self.analytics_service.flush_to_s3()
            except Exception as e:
                logger.error(f"Failed to flush to S3: {e}")
