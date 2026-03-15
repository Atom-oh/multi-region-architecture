"""Wishlist repository for DocumentDB operations."""

import logging
from datetime import datetime
from typing import Optional

from mall_common.documentdb import get_db

from app.models.wishlist import Wishlist, WishlistItem, WishlistItemCreate

logger = logging.getLogger(__name__)

COLLECTION = "wishlists"


async def get_wishlist(user_id: str) -> Optional[Wishlist]:
    db = get_db()
    doc = await db[COLLECTION].find_one({"user_id": user_id})
    if doc:
        doc.pop("_id", None)
        return Wishlist(**doc)
    return None


async def create_wishlist(user_id: str) -> Wishlist:
    db = get_db()
    wishlist = Wishlist(user_id=user_id)
    await db[COLLECTION].insert_one(wishlist.model_dump())
    logger.info("Created wishlist for user: %s", user_id)
    return wishlist


async def get_or_create_wishlist(user_id: str) -> Wishlist:
    wishlist = await get_wishlist(user_id)
    if wishlist is None:
        wishlist = await create_wishlist(user_id)
    return wishlist


async def add_item(user_id: str, item: WishlistItemCreate) -> WishlistItem:
    db = get_db()
    await get_or_create_wishlist(user_id)

    existing = await db[COLLECTION].find_one({
        "user_id": user_id,
        "items.product_id": item.product_id,
    })
    if existing:
        for existing_item in existing.get("items", []):
            if existing_item["product_id"] == item.product_id:
                return WishlistItem(**existing_item)

    new_item = WishlistItem(product_id=item.product_id, note=item.note)

    await db[COLLECTION].update_one(
        {"user_id": user_id},
        {
            "$push": {"items": new_item.model_dump()},
            "$set": {"updated_at": datetime.utcnow()},
        },
    )
    logger.info("Added item %s to wishlist for user %s", item.product_id, user_id)
    return new_item


async def remove_item(user_id: str, product_id: str) -> bool:
    db = get_db()
    result = await db[COLLECTION].update_one(
        {"user_id": user_id},
        {
            "$pull": {"items": {"product_id": product_id}},
            "$set": {"updated_at": datetime.utcnow()},
        },
    )
    removed = result.modified_count > 0
    if removed:
        logger.info("Removed item %s from wishlist for user %s", product_id, user_id)
    return removed
