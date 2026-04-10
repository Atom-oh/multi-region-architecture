"""Product service with cache-aside pattern."""

import json
import logging
from typing import Optional

from mall_common import valkey
from mall_common.kafka import Producer

from app.config import config
from app.repositories.product_repo import product_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 900  # 15 minutes

_producer: Optional[Producer] = None


def set_producer(producer: Producer) -> None:
    global _producer
    _producer = producer


def _cache_key(product_id: str) -> str:
    return f"product:{product_id}"


def _cache_key_sku(sku: str) -> str:
    return f"product:sku:{sku}"


async def list_products(
    skip: int = 0,
    limit: int = 20,
    category_id: Optional[str] = None,
    query: Optional[str] = None,
) -> tuple[list[dict], int]:
    return await product_repo.list_products(skip=skip, limit=limit, category_slug=category_id, query=query)


async def get_product(product_id: str) -> Optional[dict]:
    cache_key = _cache_key(product_id)
    cached = await valkey.get_json(cache_key)
    if cached:
        logger.debug("Cache hit for product %s", product_id)
        return cached

    product = await product_repo.get_product(product_id)
    if product:
        await valkey.set_json(cache_key, product, CACHE_TTL)
    return product


async def create_product(product_data: dict) -> dict:
    product = await product_repo.create_product(product_data)

    if _producer:
        await _producer.publish(
            "catalog.product.created",
            product["_id"],
            {"event": "product.created", "product": product},
        )

    return product


async def update_product(product_id: str, update_data: dict) -> Optional[dict]:
    update_dict = {k: v for k, v in update_data.items() if v is not None}
    product = await product_repo.update_product(product_id, update_dict)

    if product:
        await valkey.delete(_cache_key(product_id))
        if product.get("sku"):
            await valkey.delete(_cache_key_sku(product["sku"]))

        if _producer:
            await _producer.publish(
                "catalog.product.updated",
                product_id,
                {"event": "product.updated", "product": product},
            )

    return product


async def delete_product(product_id: str) -> bool:
    product = await product_repo.get_product(product_id)
    deleted = await product_repo.delete_product(product_id)

    if deleted:
        await valkey.delete(_cache_key(product_id))
        if product and product.get("sku"):
            await valkey.delete(_cache_key_sku(product["sku"]))

        if _producer:
            await _producer.publish(
                "catalog.product.deleted",
                product_id,
                {"event": "product.deleted", "product_id": product_id},
            )

    return deleted


async def list_categories() -> list[dict]:
    return await product_repo.list_categories()
