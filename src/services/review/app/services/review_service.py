"""Review service - business logic with Kafka event publishing, product enrichment, and caching."""

import logging
from typing import Optional

from mall_common import valkey
from mall_common.kafka import Producer
from mall_common.service_client import get_product, get_products_by_ids, get_user_profile

from app.models.review import Review, ReviewCreate, ReviewListResponse, ReviewUpdate
from app.repositories import review_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 600  # 10 minutes for individual reviews
LIST_CACHE_TTL = 300  # 5 minutes for review lists (more dynamic)

_producer: Optional[Producer] = None


async def _publish_event(topic: str, key: str, data: dict) -> None:
    if _producer:
        try:
            await _producer.publish(topic, key, data)
        except Exception as e:
            logger.error("Failed to publish event to %s: %s", topic, e)


async def _enrich_review(review: Review) -> Review:
    """Enrich a review with product name/image from product-catalog."""
    product = await get_product(review.product_id)
    if product:
        review.product_name = product.get("name")
        review.product_image_url = product.get("image_url")
    return review


async def _enrich_reviews(reviews: list[Review]) -> list[Review]:
    """Enrich multiple reviews with product details."""
    if not reviews:
        return reviews
    product_ids = list({r.product_id for r in reviews})
    product_map = await get_products_by_ids(product_ids)
    for review in reviews:
        catalog_data = product_map.get(review.product_id)
        if catalog_data:
            review.product_name = catalog_data.get("name")
            review.product_image_url = catalog_data.get("image_url")
    return reviews


async def get_review(review_id: str) -> Optional[Review]:
    cache_key = f"review:{review_id}"
    cached = await valkey.get_json(cache_key)
    if cached:
        logger.debug("Cache hit for review %s", review_id)
        return Review(**cached)

    review = await review_repo.get_review(review_id)
    if review:
        review = await _enrich_review(review)
        await valkey.set_json(cache_key, review.model_dump(mode="json"), CACHE_TTL)
    return review


async def get_reviews_by_product(
    product_id: str,
    page: int = 1,
    page_size: int = 10,
    sort: str = "newest",
) -> ReviewListResponse:
    cache_key = f"review:product:{product_id}:{page}:{page_size}:{sort}"
    cached = await valkey.get_json(cache_key)
    if cached:
        logger.debug("Cache hit for reviews of product %s", product_id)
        return ReviewListResponse(**cached)

    reviews, total = await review_repo.get_reviews_by_product(product_id, page, page_size, sort)
    reviews = await _enrich_reviews(reviews)
    has_more = (page * page_size) < total
    response = ReviewListResponse(
        reviews=reviews,
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more,
    )
    await valkey.set_json(cache_key, response.model_dump(mode="json"), LIST_CACHE_TTL)
    return response


async def _invalidate_review_cache(review_id: str, product_id: str) -> None:
    """Invalidate caches related to a review."""
    await valkey.delete(f"review:{review_id}")
    # Invalidate all pages and page sizes for this product's reviews
    await valkey.delete_pattern(f"review:product:{product_id}:*")


async def create_review(data: ReviewCreate) -> Review:
    review = await review_repo.create_review(data)

    # Enrich with user name from user-profile service
    profile = await get_user_profile(data.user_id)
    if profile:
        review.user_name = profile.get("name", "")
        await review_repo.update_user_name(review.id, review.user_name)

    await _invalidate_review_cache(review.id, review.product_id)

    await _publish_event(
        "reviews.created",
        review.id,
        {
            "event_type": "reviews.created",
            "review_id": review.id,
            "product_id": review.product_id,
            "user_id": review.user_id,
            "rating": review.rating,
            "timestamp": review.created_at.isoformat(),
        },
    )

    return review


async def update_review(review_id: str, update: ReviewUpdate) -> Optional[Review]:
    review = await review_repo.update_review(review_id, update)
    if review:
        await _invalidate_review_cache(review.id, review.product_id)

        await _publish_event(
            "reviews.updated",
            review.id,
            {
                "event_type": "reviews.updated",
                "review_id": review.id,
                "product_id": review.product_id,
                "rating": review.rating,
                "timestamp": review.updated_at.isoformat(),
            },
        )
    return review


async def delete_review(review_id: str) -> bool:
    review = await review_repo.get_review(review_id)
    deleted = await review_repo.delete_review(review_id)
    if deleted and review:
        await _invalidate_review_cache(review_id, review.product_id)

        await _publish_event(
            "reviews.deleted",
            review_id,
            {
                "event_type": "reviews.deleted",
                "review_id": review_id,
                "product_id": review.product_id,
                "user_id": review.user_id,
                "timestamp": review.updated_at.isoformat(),
            },
        )
    return deleted


async def increment_helpful(review_id: str) -> Optional[Review]:
    """Increment the helpful count for a review."""
    review = await review_repo.increment_helpful(review_id)
    if review:
        await valkey.delete(f"review:{review_id}")
        await valkey.delete_pattern(f"review:product:{review.product_id}:*")
    return review
