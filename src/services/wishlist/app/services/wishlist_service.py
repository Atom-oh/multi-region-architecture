"""Wishlist service - business logic with cache-aside pattern and product enrichment."""

import logging
from typing import Optional

from mall_common import valkey
from mall_common.service_client import get_products_by_ids

from app.models.wishlist import Wishlist, WishlistItem, WishlistItemCreate
from app.repositories import wishlist_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 3600  # 1 hour


def _cache_key(user_id: str) -> str:
    return f"wishlist:{user_id}"


async def _enrich_wishlist(wishlist: Wishlist) -> Wishlist:
    """Enrich wishlist items with current product data from product-catalog."""
    if not wishlist.items:
        return wishlist
    product_ids = [item.product_id for item in wishlist.items]
    product_map = await get_products_by_ids(product_ids)
    for item in wishlist.items:
        catalog_data = product_map.get(item.product_id)
        if catalog_data:
            item.name = catalog_data.get("name", item.name)
            current_price = catalog_data.get("price")
            if current_price is not None and current_price != item.price:
                item.original_price = item.price
                item.price = current_price
                item.price_dropped = current_price < (item.original_price or item.price)
            item.image_url = catalog_data.get("image_url", item.image_url)
            stock = catalog_data.get("stock", 0)
            if isinstance(stock, dict):
                stock = stock.get("available", 0)
            item.in_stock = stock > 0
    return wishlist


async def get_wishlist(user_id: str) -> Wishlist:
    cache_key = _cache_key(user_id)

    try:
        cached = await valkey.get_json(cache_key)
        if cached:
            logger.debug("Cache hit for wishlist user_id=%s", user_id)
            wishlist = Wishlist(**cached)
            return await _enrich_wishlist(wishlist)
    except Exception as e:
        logger.warning("Cache read failed: %s", e)

    wishlist = await wishlist_repo.get_or_create_wishlist(user_id)
    wishlist = await _enrich_wishlist(wishlist)

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
