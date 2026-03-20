"""Wishlist service - business logic with cache-aside pattern."""

import logging
from typing import Optional

from mall_common import valkey

from app.models.wishlist import Wishlist, WishlistItem, WishlistItemCreate
from app.repositories import wishlist_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 3600  # 1 hour


def _cache_key(user_id: str) -> str:
    return f"wishlist:{user_id}"


async def get_wishlist(user_id: str) -> Wishlist:
    cache_key = _cache_key(user_id)

    try:
        cached = await valkey.get_json(cache_key)
        if cached:
            logger.debug("Cache hit for wishlist user_id=%s", user_id)
            return Wishlist(**cached)
    except Exception as e:
        logger.warning("Cache read failed: %s", e)

    wishlist = await wishlist_repo.get_or_create_wishlist(user_id)

    try:
        await valkey.set_json(cache_key, wishlist.model_dump(), ttl_seconds=CACHE_TTL)
    except Exception as e:
        logger.warning("Cache write failed: %s", e)

    return wishlist


async def add_item(user_id: str, item: WishlistItemCreate) -> WishlistItem:
    new_item = await wishlist_repo.add_item(user_id, item)

    try:
        await valkey.delete(_cache_key(user_id))
    except Exception as e:
        logger.warning("Cache invalidation failed: %s", e)

    return new_item


async def remove_item(user_id: str, product_id: str) -> bool:
    removed = await wishlist_repo.remove_item(user_id, product_id)

    if removed:
        try:
            await valkey.delete(_cache_key(user_id))
        except Exception as e:
            logger.warning("Cache invalidation failed: %s", e)

    return removed
