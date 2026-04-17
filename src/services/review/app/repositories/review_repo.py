"""Review repository for DocumentDB operations."""

import logging
from datetime import datetime
from typing import Optional
from uuid import uuid4

from mall_common.documentdb import get_db, get_write_db

from app.models.review import Review, ReviewCreate, ReviewUpdate

logger = logging.getLogger(__name__)

COLLECTION = "reviews"


async def get_review(review_id: str) -> Optional[Review]:
    db = get_db()
    doc = await db[COLLECTION].find_one({"id": review_id})
    if doc:
        doc.pop("_id", None)
        return Review(**doc)
    return None


SORT_MAP = {
    "newest": ("created_at", -1),
    "oldest": ("created_at", 1),
    "highest": ("rating", -1),
    "lowest": ("rating", 1),
    "helpful": ("helpful_count", -1),
}


async def get_reviews_by_product(
    product_id: str,
    page: int = 1,
    page_size: int = 10,
    sort: str = "newest",
) -> tuple[list[Review], int]:
    db = get_db()
    skip = (page - 1) * page_size
    sort_field, sort_dir = SORT_MAP.get(sort, ("created_at", -1))

    cursor = db[COLLECTION].find({"product_id": product_id}).sort(sort_field, sort_dir).skip(skip).limit(page_size)

    reviews = []
    async for doc in cursor:
        doc.pop("_id", None)
        reviews.append(Review(**doc))

    total = await db[COLLECTION].count_documents({"product_id": product_id})

    return reviews, total


async def create_review(data: ReviewCreate) -> Review:
    db = get_write_db()
    review = Review(
        id=str(uuid4()),
        user_id=data.user_id,
        product_id=data.product_id,
        rating=data.rating,
        title=data.title,
        body=data.body,
        verified_purchase=data.verified_purchase,
    )
    await db[COLLECTION].insert_one(review.model_dump())
    logger.info("Created review %s for product %s by user %s", review.id, review.product_id, review.user_id)
    return review


async def update_review(review_id: str, update: ReviewUpdate) -> Optional[Review]:
    db = get_write_db()
    update_data = {k: v for k, v in update.model_dump().items() if v is not None}
    if not update_data:
        return await get_review(review_id)

    update_data["updated_at"] = datetime.utcnow()

    result = await db[COLLECTION].find_one_and_update(
        {"id": review_id},
        {"$set": update_data},
        return_document=True,
    )
    if result:
        result.pop("_id", None)
        logger.info("Updated review %s", review_id)
        return Review(**result)
    return None


async def update_user_name(review_id: str, user_name: str) -> None:
    db = get_write_db()
    await db[COLLECTION].update_one({"id": review_id}, {"$set": {"user_name": user_name}})


async def increment_helpful(review_id: str) -> Optional[Review]:
    db = get_write_db()
    result = await db[COLLECTION].find_one_and_update(
        {"id": review_id},
        {"$inc": {"helpful_count": 1}},
        return_document=True,
    )
    if result:
        result.pop("_id", None)
        return Review(**result)
    return None


async def delete_review(review_id: str) -> bool:
    db = get_write_db()
    result = await db[COLLECTION].delete_one({"id": review_id})
    deleted = result.deleted_count > 0
    if deleted:
        logger.info("Deleted review %s", review_id)
    return deleted
