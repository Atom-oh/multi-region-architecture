"""Review service - business logic with Kafka event publishing."""

import logging
from typing import Optional

from mall_common.kafka import Producer

from app.config import config
from app.models.review import Review, ReviewCreate, ReviewListResponse, ReviewUpdate
from app.repositories import review_repo

logger = logging.getLogger(__name__)

_producer: Optional[Producer] = None


async def init_producer() -> None:
    global _producer
    _producer = Producer(config.kafka_brokers)
    await _producer.start()
    logger.info("Kafka producer initialized")


async def stop_producer() -> None:
    global _producer
    if _producer:
        await _producer.stop()
        _producer = None


async def _publish_event(topic: str, key: str, data: dict) -> None:
    if _producer:
        try:
            await _producer.publish(topic, key, data)
        except Exception as e:
            logger.error("Failed to publish event to %s: %s", topic, e)


async def get_review(review_id: str) -> Optional[Review]:
    return await review_repo.get_review(review_id)


async def get_reviews_by_product(
    product_id: str,
    page: int = 1,
    page_size: int = 10,
) -> ReviewListResponse:
    reviews, total = await review_repo.get_reviews_by_product(product_id, page, page_size)
    has_more = (page * page_size) < total
    return ReviewListResponse(
        reviews=reviews,
        total=total,
        page=page,
        page_size=page_size,
        has_more=has_more,
    )


async def create_review(data: ReviewCreate) -> Review:
    review = await review_repo.create_review(data)

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
