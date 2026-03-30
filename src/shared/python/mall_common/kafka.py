"""Kafka producer and consumer using aiokafka."""

import json
import logging
import os
import ssl
from collections.abc import Callable, Coroutine
from typing import Any

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

from mall_common.tracing import KafkaTraceExtractor, KafkaTraceInjector

logger = logging.getLogger(__name__)


def _get_sasl_config() -> dict:
    """Get SASL/SCRAM configuration for MSK if credentials are provided."""
    username = os.getenv("MSK_USERNAME", "")
    password = os.getenv("MSK_PASSWORD", "")

    config = {
        "security_protocol": "SASL_SSL",
        "ssl_context": ssl.create_default_context(),
    }

    if username and password:
        config["sasl_mechanism"] = "SCRAM-SHA-512"
        config["sasl_plain_username"] = username
        config["sasl_plain_password"] = password
        logger.info("SASL/SCRAM-SHA-512 authentication configured for Kafka")
    else:
        # Fall back to SSL only (for IAM auth or no auth scenarios)
        config["security_protocol"] = "SSL"
        logger.info("No MSK_USERNAME/MSK_PASSWORD set, using SSL only")

    return config


class Producer:
    def __init__(self, brokers: str):
        sasl_config = _get_sasl_config()
        self._producer = AIOKafkaProducer(
            bootstrap_servers=brokers,
            value_serializer=lambda v: json.dumps(v).encode(),
            key_serializer=lambda k: k.encode() if k else None,
            **sasl_config,
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
        sasl_config = _get_sasl_config()

        # Use AZ-local brokers if KAFKA_BROKERS_LOCAL is set
        effective_brokers = os.getenv("KAFKA_BROKERS_LOCAL", "") or brokers

        consumer_kwargs: dict[str, Any] = {
            "bootstrap_servers": effective_brokers,
            "group_id": group_id,
            "value_deserializer": lambda v: json.loads(v.decode()),
            "auto_offset_reset": "earliest",
            **sasl_config,
        }

        # Pass client_rack for rack-aware partition assignment if set
        client_rack = os.getenv("CLIENT_RACK", "")
        if client_rack:
            consumer_kwargs["client_id"] = f"{group_id}-{client_rack}"

        self._consumer = AIOKafkaConsumer(
            topic,
            **consumer_kwargs,
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
