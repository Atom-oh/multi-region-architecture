"""Analytics Service - FastAPI Application with DB-driven responses."""

import logging
from datetime import datetime
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.documentdb import connect, disconnect, get_db
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.service_client import get_products_by_ids
from mall_common.tracing import init_tracing

from app.config import settings as config

logger = logging.getLogger(__name__)
# pymongo.DESCENDING = -1
DESCENDING = -1
app = FastAPI(redirect_slashes=False, title="Analytics Service", version="1.0.0")
_db_connected = False

# Event consumer for analytics - initialized on startup
_event_consumer = None

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_tracing(config.service_name, app)
app.include_router(health_router)


def _empty_dashboard() -> dict:
    """Return an empty dashboard structure with zeroed metrics."""
    return {
        "total_users": 0,
        "active_users_today": 0,
        "new_users_today": 0,
        "total_orders": 0,
        "orders_today": 0,
        "revenue_today": 0,
        "revenue_month": 0,
        "conversion_rate": 0.0,
        "avg_order_value": 0,
        "cart_abandonment_rate": 0.0,
        "top_products": [],
        "top_categories": [],
        "traffic_sources": [],
    }


@app.get("/")
async def root():
    return {"service": "analytics", "status": "running"}


@app.post("/api/v1/analytics/events")
async def track_event(event: dict):
    """Track an analytics event (stub - returns acknowledgment)."""
    return {
        "status": "received",
        "event_id": f"evt-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "event_type": event.get("type", "unknown"),
        "timestamp": datetime.utcnow().isoformat(),
        "message": "이벤트가 기록되었습니다",
    }


@app.get("/api/v1/analytics/dashboard")
async def get_dashboard(period: str = "today"):
    """Get analytics dashboard data from DocumentDB. Returns empty metrics when DB is unavailable."""
    if _db_connected:
        try:
            db = get_db()
            # Aggregation: count products by category
            category_pipeline = [
                {"$group": {"_id": "$category.slug", "count": {"$sum": 1}, "avgRating": {"$avg": "$rating"}}}
            ]
            category_cursor = db["products"].aggregate(category_pipeline)
            categories = []
            async for doc in category_cursor:
                categories.append({
                    "name": doc["_id"],
                    "count": doc["count"],
                    "avg_rating": round(doc.get("avgRating", 0) or 0, 1),
                })
            # Get total product count
            total_products = await db["products"].count_documents({})
            # Get order stats
            total_orders = await db["orders"].count_documents({}) if "orders" in await db.list_collection_names() else 0
            # Get user activity stats
            total_activities = await db["user_activities"].count_documents({}) if "user_activities" in await db.list_collection_names() else 0
            return {
                "period": period,
                "generated_at": datetime.utcnow().isoformat(),
                "metrics": {
                    **_empty_dashboard(),
                    "total_products": total_products,
                    "total_orders": total_orders,
                    "total_activities": total_activities,
                    "top_categories": categories,
                },
                "currency": "KRW",
            }
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, returning empty dashboard")
    # Fallback to empty dashboard when DB is unavailable
    return {
        "period": period,
        "generated_at": datetime.utcnow().isoformat(),
        "metrics": _empty_dashboard(),
        "currency": "KRW",
    }


@app.get("/api/v1/analytics/top-products")
async def get_top_products(limit: int = 10):
    """Get top products from user_activities aggregation, enriched via product-catalog service."""
    if _db_connected:
        try:
            db = get_db()
            collections = await db.list_collection_names()

            # Try user_activities aggregation first for real engagement-based ranking
            if "user_activities" in collections:
                pipeline = [
                    {"$match": {"action": {"$in": ["purchase", "add_to_cart", "view", "click"]}}},
                    {"$group": {
                        "_id": "$product_id",
                        "score": {"$sum": {
                            "$switch": {
                                "branches": [
                                    {"case": {"$eq": ["$action", "purchase"]}, "then": 10},
                                    {"case": {"$eq": ["$action", "add_to_cart"]}, "then": 5},
                                    {"case": {"$eq": ["$action", "click"]}, "then": 2},
                                ],
                                "default": 1,
                            }
                        }},
                        "interaction_count": {"$sum": 1},
                    }},
                    {"$sort": {"score": DESCENDING}},
                    {"$limit": limit},
                ]
                cursor = db["user_activities"].aggregate(pipeline)
                top_items = []
                async for doc in cursor:
                    top_items.append(doc)

                if top_items:
                    # Enrich with product details from product-catalog service
                    product_ids = [item["_id"] for item in top_items if item["_id"]]
                    product_map = await get_products_by_ids(product_ids)

                    products = []
                    for item in top_items:
                        pid = item["_id"]
                        catalog_data = product_map.get(pid, {})
                        products.append({
                            "product_id": pid,
                            "name": catalog_data.get("name", f"Product {pid}"),
                            "score": item.get("score", 0),
                            "interaction_count": item.get("interaction_count", 0),
                            "price": catalog_data.get("price"),
                            "image_url": catalog_data.get("image_url"),
                            "category": catalog_data.get("category"),
                        })
                    return {
                        "top_products": products,
                        "total": len(products),
                        "generated_at": datetime.utcnow().isoformat(),
                    }

            # Fallback: sort products by rating from products collection
            if "products" in collections:
                cursor = db["products"].find().sort("rating", DESCENDING).limit(limit)
                products = []
                async for doc in cursor:
                    doc["_id"] = str(doc["_id"])
                    products.append(doc)
                return {
                    "top_products": products,
                    "total": len(products),
                    "generated_at": datetime.utcnow().isoformat(),
                }
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, returning empty top products")
    # Return empty list when DB is unavailable
    return {
        "top_products": [],
        "total": 0,
        "generated_at": datetime.utcnow().isoformat(),
    }


@app.get("/api/v1/analytics/reports")
async def list_reports(report_type: str = None, limit: int = 10):
    """List available analytics reports from DocumentDB. Returns empty list when DB is unavailable."""
    if _db_connected:
        try:
            db = get_db()
            collections = await db.list_collection_names()
            if "reports" in collections:
                query = {}
                if report_type:
                    query["type"] = report_type
                cursor = db["reports"].find(query).sort("created_at", DESCENDING).limit(limit)
                reports = []
                async for doc in cursor:
                    doc["_id"] = str(doc["_id"])
                    reports.append(doc)
                return {
                    "reports": reports,
                    "total": len(reports),
                }
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, returning empty reports")
    return {
        "reports": [],
        "total": 0,
    }


@app.on_event("startup")
async def startup():
    global _db_connected, _event_consumer

    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            _db_connected = True
            logger.info("Connected to DocumentDB")
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, endpoints will return empty data")

    # Initialize Kafka consumer for all events (graceful degradation)
    if config.kafka_brokers and config.kafka_brokers != "localhost:9092":
        try:
            from app.consumers.all_events_consumer import EventConsumer
            from app.services.analytics_service import AnalyticsService

            analytics_service = AnalyticsService()
            _event_consumer = EventConsumer(config, analytics_service)
            await _event_consumer.start()
            # Start consuming in background task
            import asyncio
            asyncio.create_task(_event_consumer.consume())
            logger.info(f"Event consumer started for brokers: {config.kafka_brokers}")
        except Exception as e:
            logger.warning(f"Kafka unavailable: {e}, event consumer disabled")
    else:
        logger.info(f"No MSK brokers configured (KAFKA_BROKERS={config.kafka_brokers}), event consumer disabled")

    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _event_consumer

    await disconnect()

    if _event_consumer:
        try:
            await _event_consumer.stop()
            logger.info("Event consumer stopped")
        except Exception as e:
            logger.warning(f"Error stopping event consumer: {e}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
