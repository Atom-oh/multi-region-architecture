"""Analytics Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="analytics")
app = FastAPI(title="Analytics Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock analytics data
MOCK_DASHBOARD = {
    "total_users": 15420,
    "active_users_today": 3251,
    "total_orders": 8934,
    "revenue_today": 45231.50,
    "revenue_month": 1234567.89,
    "conversion_rate": 3.2,
    "avg_order_value": 85.50,
    "top_categories": [
        {"name": "electronics", "sales": 4521},
        {"name": "clothing", "sales": 3210},
        {"name": "home", "sales": 2150},
    ],
}

MOCK_REPORTS = [
    {"id": "rpt-001", "name": "Daily Sales Report", "type": "sales", "created_at": "2026-03-20T00:00:00Z"},
    {"id": "rpt-002", "name": "User Engagement Report", "type": "engagement", "created_at": "2026-03-19T00:00:00Z"},
    {"id": "rpt-003", "name": "Inventory Analysis", "type": "inventory", "created_at": "2026-03-18T00:00:00Z"},
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
    }


@app.get("/api/v1/analytics/dashboard")
async def get_dashboard(period: str = "today"):
    """Get analytics dashboard data."""
    return {
        "period": period,
        "generated_at": datetime.utcnow().isoformat(),
        "metrics": MOCK_DASHBOARD,
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
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
