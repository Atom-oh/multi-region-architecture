"""Recommendation service with caching and inter-service enrichment."""

import logging
from collections import Counter
from datetime import datetime

from mall_common import valkey
from mall_common.service_client import get_products_by_ids, get_user_profile

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

        # Fetch user profile for preference-based score weighting
        profile = await get_user_profile(user_id)
        preferred_categories = []
        if profile:
            preferred_categories = profile.get("preferred_categories", [])

        recommendations = self._generate_recommendations(activities, limit, preferred_categories)

        # Enrich with product details from product-catalog
        recommendations = await self._enrich_recommendations(recommendations)

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

        # Collect product IDs for batch enrichment
        product_ids = [item["_id"] for item in trending_data]
        product_map = await get_products_by_ids(product_ids)

        products = []
        for item in trending_data:
            pid = item["_id"]
            catalog_data = product_map.get(pid, {})
            cat = catalog_data.get("category", "general")
            if isinstance(cat, dict):
                cat = cat.get("slug", "general")
            products.append(
                TrendingProduct(
                    product_id=pid,
                    name=catalog_data.get("name", f"Product {pid}"),
                    category=cat,
                    score=item.get("score", 0),
                    view_count=item.get("view_count", 0),
                    purchase_count=item.get("purchase_count", 0),
                )
            )

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

        # Enrich with product details
        similar = await self._enrich_recommendations(similar)

        response = SimilarProductsResponse(
            product_id=product_id,
            similar=similar,
            generated_at=datetime.utcnow(),
        )

        await valkey.set_json(cache_key, response.model_dump(mode="json"), CACHE_TTL_SECONDS)
        logger.info("Generated and cached similar products for %s", product_id)

        return response

    async def get_recommendations_by_category(self, category: str, limit: int = 10) -> dict:
        """Get recommendations filtered by category."""
        cache_key = f"recommendations:category:{category}"

        cached = await valkey.get_json(cache_key)
        if cached:
            return cached

        trending_data = await recommendation_repo.get_trending_products(limit * 2)
        product_ids = [item["_id"] for item in trending_data]
        product_map = await get_products_by_ids(product_ids)

        # Filter by category
        recommendations = []
        for item in trending_data:
            pid = item["_id"]
            catalog_data = product_map.get(pid, {})
            if catalog_data.get("category") == category:
                recommendations.append({
                    "product_id": pid,
                    "name": catalog_data.get("name", f"Product {pid}"),
                    "price": catalog_data.get("price"),
                    "image_url": catalog_data.get("image_url"),
                    "score": item.get("score", 0),
                })
            if len(recommendations) >= limit:
                break

        response = {
            "category": category,
            "recommendations": recommendations,
            "total": len(recommendations),
        }

        await valkey.set_json(cache_key, response, CACHE_TTL_SECONDS)
        return response

    async def get_random_recommendations(self, limit: int = 10) -> dict:
        """Get random product recommendations."""
        trending = await recommendation_repo.get_trending_products(limit)
        product_ids = [item["_id"] for item in trending]
        product_map = await get_products_by_ids(product_ids)

        recommendations = []
        for item in trending:
            pid = item["_id"]
            catalog_data = product_map.get(pid, {})
            recommendations.append({
                "product_id": pid,
                "name": catalog_data.get("name", f"Product {pid}"),
                "price": catalog_data.get("price"),
                "image_url": catalog_data.get("image_url"),
                "score": item.get("score", 0),
            })

        return {
            "recommendations": recommendations,
            "total": len(recommendations),
            "algorithm": "random_sample",
        }

    def _generate_recommendations(
        self, activities: list[dict], limit: int, preferred_categories: list[str] | None = None
    ) -> list[Recommendation]:
        if not activities:
            return []

        product_scores: dict[str, float] = {}
        action_weights = {"purchase": 1.0, "add_to_cart": 0.7, "click": 0.3, "view": 0.1}

        for activity in activities:
            product_id = activity.get("product_id")
            action = activity.get("action", "view")
            weight = action_weights.get(action, 0.1)

            # Boost score for preferred categories
            category = activity.get("category", "")
            if preferred_categories and category in preferred_categories:
                weight *= 1.5

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

    async def _enrich_recommendations(self, recommendations: list[Recommendation]) -> list[Recommendation]:
        """Enrich recommendations with product name/price/image from product-catalog."""
        if not recommendations:
            return recommendations

        product_ids = [r.product_id for r in recommendations]
        product_map = await get_products_by_ids(product_ids)

        for rec in recommendations:
            catalog_data = product_map.get(rec.product_id)
            if catalog_data:
                rec.name = catalog_data.get("name")
                rec.price = catalog_data.get("price")
                rec.image_url = catalog_data.get("image_url")
                cat = catalog_data.get("category")
                rec.category = cat.get("slug") if isinstance(cat, dict) else cat

        return recommendations


recommendation_service = RecommendationService()
