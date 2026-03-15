"""Repository for recommendation data in DocumentDB."""

import logging
from datetime import datetime, timedelta
from typing import Any

from mall_common.documentdb import get_db

logger = logging.getLogger(__name__)


class RecommendationRepository:
    def __init__(self):
        self._recommendations_collection = "recommendations"
        self._activities_collection = "user_activities"

    @property
    def recommendations(self):
        return get_db()[self._recommendations_collection]

    @property
    def activities(self):
        return get_db()[self._activities_collection]

    async def get_user_activities(self, user_id: str, limit: int = 100) -> list[dict]:
        cursor = self.activities.find({"user_id": user_id}).sort("timestamp", -1).limit(limit)
        return await cursor.to_list(length=limit)

    async def save_activity(self, activity: dict) -> str:
        result = await self.activities.insert_one(activity)
        logger.debug("Saved activity for user %s", activity.get("user_id"))
        return str(result.inserted_id)

    async def get_cached_recommendations(self, user_id: str) -> dict | None:
        doc = await self.recommendations.find_one({"user_id": user_id})
        if doc and doc.get("expires_at", datetime.min) > datetime.utcnow():
            return doc
        return None

    async def cache_recommendations(self, user_id: str, recommendations: list[dict], ttl_hours: int = 1) -> None:
        expires_at = datetime.utcnow() + timedelta(hours=ttl_hours)
        await self.recommendations.update_one(
            {"user_id": user_id},
            {
                "$set": {
                    "user_id": user_id,
                    "recommendations": recommendations,
                    "updated_at": datetime.utcnow(),
                    "expires_at": expires_at,
                }
            },
            upsert=True,
        )
        logger.debug("Cached recommendations for user %s", user_id)

    async def get_trending_products(self, limit: int = 10) -> list[dict]:
        pipeline = [
            {"$match": {"action": {"$in": ["view", "purchase"]}}},
            {"$group": {
                "_id": "$product_id",
                "view_count": {"$sum": {"$cond": [{"$eq": ["$action", "view"]}, 1, 0]}},
                "purchase_count": {"$sum": {"$cond": [{"$eq": ["$action", "purchase"]}, 1, 0]}},
            }},
            {"$addFields": {
                "score": {"$add": [
                    {"$multiply": ["$view_count", 0.1]},
                    {"$multiply": ["$purchase_count", 1.0]},
                ]},
            }},
            {"$sort": {"score": -1}},
            {"$limit": limit},
        ]
        cursor = self.activities.aggregate(pipeline)
        return await cursor.to_list(length=limit)

    async def get_similar_product_activities(self, product_id: str, limit: int = 100) -> list[dict]:
        users_cursor = self.activities.find({"product_id": product_id}).distinct("user_id")
        users = await users_cursor if hasattr(users_cursor, '__await__') else users_cursor

        if not users:
            return []

        cursor = self.activities.find({
            "user_id": {"$in": users[:50]},
            "product_id": {"$ne": product_id},
        }).limit(limit)
        return await cursor.to_list(length=limit)


recommendation_repo = RecommendationRepository()
