"""Recommendation service with caching."""

import logging
from collections import Counter
from datetime import datetime

from mall_common import valkey

from app.models.recommendation import (
    Recommendation,
    RecommendationResponse,
    SimilarProductsResponse,
    TrendingProduct,
    TrendingResponse,
)
from app.repositories.recommendation_repo import recommendation_repo

logger = logging.getLogger(__name__)

CACHE_TTL_SECONDS = 3600  # 1 hour


class RecommendationService:
    async def get_personalized_recommendations(self, user_id: str, limit: int = 10) -> RecommendationResponse:
        cache_key = f"recommendations:{user_id}"

        cached = await valkey.get_json(cache_key)
        if cached:
            logger.debug("Cache hit for user %s recommendations", user_id)
            return RecommendationResponse(**cached)

        activities = await recommendation_repo.get_user_activities(user_id)

        recommendations = self._generate_recommendations(activities, limit)

        response = RecommendationResponse(
            user_id=user_id,
            recommendations=recommendations,
            generated_at=datetime.utcnow(),
        )

        await valkey.set_json(cache_key, response.model_dump(mode="json"), CACHE_TTL_SECONDS)
        logger.info("Generated and cached recommendations for user %s", user_id)

        return response

    async def get_trending_products(self, limit: int = 10) -> TrendingResponse:
        cache_key = "recommendations:trending"

        cached = await valkey.get_json(cache_key)
        if cached:
            logger.debug("Cache hit for trending products")
            return TrendingResponse(**cached)

        trending_data = await recommendation_repo.get_trending_products(limit)

        products = [
            TrendingProduct(
                product_id=item["_id"],
                name=f"Product {item['_id']}",
                category="general",
                score=item.get("score", 0),
                view_count=item.get("view_count", 0),
                purchase_count=item.get("purchase_count", 0),
            )
            for item in trending_data
        ]

        response = TrendingResponse(products=products, generated_at=datetime.utcnow())

        await valkey.set_json(cache_key, response.model_dump(mode="json"), CACHE_TTL_SECONDS)
        logger.info("Generated and cached trending products")

        return response

    async def get_similar_products(self, product_id: str, limit: int = 10) -> SimilarProductsResponse:
        cache_key = f"recommendations:similar:{product_id}"

        cached = await valkey.get_json(cache_key)
        if cached:
            logger.debug("Cache hit for similar products to %s", product_id)
            return SimilarProductsResponse(**cached)

        activities = await recommendation_repo.get_similar_product_activities(product_id)

        product_counts = Counter(a["product_id"] for a in activities)
        top_products = product_counts.most_common(limit)

        similar = [
            Recommendation(
                product_id=pid,
                score=min(count / 10.0, 1.0),
                reason="Users who viewed this also viewed",
            )
            for pid, count in top_products
        ]

        response = SimilarProductsResponse(
            product_id=product_id,
            similar=similar,
            generated_at=datetime.utcnow(),
        )

        await valkey.set_json(cache_key, response.model_dump(mode="json"), CACHE_TTL_SECONDS)
        logger.info("Generated and cached similar products for %s", product_id)

        return response

    def _generate_recommendations(self, activities: list[dict], limit: int) -> list[Recommendation]:
        if not activities:
            return []

        product_scores: dict[str, float] = {}
        action_weights = {"purchase": 1.0, "add_to_cart": 0.7, "click": 0.3, "view": 0.1}

        for activity in activities:
            product_id = activity.get("product_id")
            action = activity.get("action", "view")
            weight = action_weights.get(action, 0.1)

            product_scores[product_id] = product_scores.get(product_id, 0) + weight

        sorted_products = sorted(product_scores.items(), key=lambda x: x[1], reverse=True)[:limit]

        return [
            Recommendation(
                product_id=pid,
                score=min(score / 10.0, 1.0),
                reason="Based on your browsing history",
            )
            for pid, score in sorted_products
        ]


recommendation_service = RecommendationService()
