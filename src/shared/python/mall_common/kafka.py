"""Kafka producer and consumer using aiokafka."""

import json
import logging
from collections.abc import Callable, Coroutine
from typing import Any

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

from mall_common.tracing import KafkaTraceExtractor, KafkaTraceInjector

logger = logging.getLogger(__name__)


class Producer:
    def __init__(self, brokers: str):
        self._producer = AIOKafkaProducer(
            bootstrap_servers=brokers,
            value_serializer=lambda v: json.dumps(v).encode(),
            key_serializer=lambda k: k.encode() if k else None,
        )

    async def start(self) -> None:
        await self._producer.start()

    async def stop(self) -> None:
        await self._producer.stop()

    async def publish(self, topic: str, key: str, value: Any) -> None:
        headers = KafkaTraceInjector.inject_headers()
        await self._producer.send_and_wait(topic, value=value, key=key, headers=headers)
        logger.debug("Published to %s key=%s", topic, key)


class Consumer:
    def __init__(
        self,
        brokers: str,
        topic: str,
        group_id: str,
        handler: Callable[[str, Any], Coroutine],
    ):
        self._consumer = AIOKafkaConsumer(
            topic,
            bootstrap_servers=brokers,
            group_id=group_id,
            value_deserializer=lambda v: json.loads(v.decode()),
            auto_offset_reset="earliest",
        )
        self._handler = handler

    async def start(self) -> None:
        await self._consumer.start()
        logger.info("Consumer started for topic: %s", self._consumer.subscription())

    async def stop(self) -> None:
        await self._consumer.stop()

    async def consume(self) -> None:
        from opentelemetry import context as otel_context

        async for msg in self._consumer:
            try:
                ctx = KafkaTraceExtractor.extract_context(msg.headers)
                token = otel_context.attach(ctx)
                try:
                    key = msg.key.decode() if msg.key else ""
                    await self._handler(key, msg.value)
                finally:
                    otel_context.detach(token)
            except Exception:
                logger.exception("Failed to handle message key=%s", msg.key)
