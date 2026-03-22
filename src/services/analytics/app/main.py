"""Analytics Service - FastAPI Application with stub responses."""

import logging
from datetime import datetime
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.documentdb import connect, disconnect, get_db
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

logger = logging.getLogger(__name__)
# pymongo.DESCENDING = -1
DESCENDING = -1
config = ServiceConfig(service_name="analytics")
app = FastAPI(title="Analytics Service", version="1.0.0")
_db_connected = False

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

# Mock analytics data - consistent with Korean mall theme
MOCK_DASHBOARD = {
    "total_users": 125420,
    "active_users_today": 8251,
    "new_users_today": 342,
    "total_orders": 89340,
    "orders_today": 1523,
    "revenue_today": 245231500,  # 245,231,500원
    "revenue_month": 7834567890,  # 7,834,567,890원
    "conversion_rate": 3.8,
    "avg_order_value": 156500,  # 156,500원
    "cart_abandonment_rate": 68.5,
    "top_products": [
        {
            "product_id": "PRD-001",
            "name": "삼성 갤럭시 S25 울트라",
            "sales": 4521,
            "revenue": 8544690000,
        },
        {
            "product_id": "PRD-003",
            "name": "다이슨 에어랩",
            "sales": 3210,
            "revenue": 2243790000,
        },
        {
            "product_id": "PRD-007",
            "name": "LG 올레드 TV 65\"",
            "sales": 2150,
            "revenue": 7073500000,
        },
        {
            "product_id": "PRD-004",
            "name": "애플 맥북 프로 M4",
            "sales": 1892,
            "revenue": 5657080000,
        },
        {
            "product_id": "PRD-010",
            "name": "소니 WH-1000XM5",
            "sales": 1567,
            "revenue": 672243000,
        },
    ],
    "top_categories": [
        {"name": "electronics", "display_name": "전자제품", "sales": 12521, "revenue": 22547933000},
        {"name": "shoes", "display_name": "신발", "sales": 5210, "revenue": 1062420000},
        {"name": "kitchen", "display_name": "주방용품", "sales": 3150, "revenue": 1584750000},
        {"name": "beauty", "display_name": "뷰티", "sales": 3210, "revenue": 2243790000},
        {"name": "fashion", "display_name": "패션", "sales": 8920, "revenue": 258680000},
    ],
    "traffic_sources": [
        {"source": "organic", "display_name": "자연검색", "visitors": 45000, "percentage": 35.2},
        {"source": "direct", "display_name": "직접방문", "visitors": 32000, "percentage": 25.0},
        {"source": "social", "display_name": "소셜미디어", "visitors": 28000, "percentage": 21.9},
        {"source": "paid", "display_name": "유료광고", "visitors": 15000, "percentage": 11.7},
        {"source": "referral", "display_name": "추천", "visitors": 7920, "percentage": 6.2},
    ],
}

MOCK_REPORTS = [
    {
        "id": "rpt-001",
        "name": "일간 매출 리포트",
        "type": "sales",
        "period": "daily",
        "created_at": "2026-03-20T00:00:00Z",
        "summary": {
            "total_revenue": 245231500,
            "total_orders": 1523,
            "avg_order_value": 161019,
        },
    },
    {
        "id": "rpt-002",
        "name": "주간 사용자 분석 리포트",
        "type": "engagement",
        "period": "weekly",
        "created_at": "2026-03-19T00:00:00Z",
        "summary": {
            "active_users": 52341,
            "session_duration_avg": "8분 32초",
            "pages_per_session": 5.7,
        },
    },
    {
        "id": "rpt-003",
        "name": "월간 재고 분석 리포트",
        "type": "inventory",
        "period": "monthly",
        "created_at": "2026-03-18T00:00:00Z",
        "summary": {
            "total_sku": 10523,
            "low_stock_items": 156,
            "out_of_stock": 23,
        },
    },
    {
        "id": "rpt-004",
        "name": "카테고리별 실적 리포트",
        "type": "category",
        "period": "monthly",
        "created_at": "2026-03-17T00:00:00Z",
        "summary": {
            "top_category": "electronics",
            "growth_rate": 15.3,
            "new_products": 234,
        },
    },
]


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
    """Get analytics dashboard data."""
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
            return {
                "period": period,
                "generated_at": datetime.utcnow().isoformat(),
                "metrics": {
                    **MOCK_DASHBOARD,
                    "total_products": total_products,
                    "categories_from_db": categories,
                },
                "currency": "KRW",
            }
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, using fallback mock data")
    # Fallback to mock data
    return {
        "period": period,
        "generated_at": datetime.utcnow().isoformat(),
        "metrics": MOCK_DASHBOARD,
        "currency": "KRW",
    }


@app.get("/api/v1/analytics/top-products")
async def get_top_products(limit: int = 10):
    """Get top products by rating."""
    if _db_connected:
        try:
            db = get_db()
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
            logger.warning(f"DocumentDB query failed: {e}, using fallback mock data")
    # Fallback to mock data
    return {
        "top_products": MOCK_DASHBOARD.get("top_products", [])[:limit],
        "total": len(MOCK_DASHBOARD.get("top_products", [])),
        "generated_at": datetime.utcnow().isoformat(),
    }


@app.get("/api/v1/analytics/reports")
async def list_reports(report_type: str = None, limit: int = 10):
    """List available analytics reports."""
    reports = MOCK_REPORTS
    if report_type:
        reports = [r for r in reports if r["type"] == report_type]
    return {
        "reports": reports[:limit],
        "total": len(reports),
    }


@app.on_event("startup")
async def startup():
    global _db_connected
    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            _db_connected = True
            logger.info("Connected to DocumentDB")
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, using fallback mock data")
    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    await disconnect()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
