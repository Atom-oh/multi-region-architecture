"""Analytics API router."""

from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Query

from ..models.analytics import AnalyticsQuery, DashboardMetrics, EventRecord
from ..services.analytics_service import analytics_service

router = APIRouter(prefix="/api/v1/analytics", tags=["analytics"])


@router.get("/dashboard", response_model=DashboardMetrics)
async def get_dashboard():
    """Get aggregated dashboard metrics."""
    return await analytics_service.get_dashboard_metrics()


@router.get("/events", response_model=list[EventRecord])
async def get_events(
    topic: Optional[str] = Query(None, description="Filter by topic"),
    start_time: Optional[datetime] = Query(None, description="Start of time range"),
    end_time: Optional[datetime] = Query(None, description="End of time range"),
    limit: int = Query(100, ge=1, le=1000, description="Maximum number of events to return"),
):
    """Get recent events with optional filtering."""
    return await analytics_service.get_events(
        topic=topic,
        start_time=start_time,
        end_time=end_time,
        limit=limit,
    )


@router.post("/query")
async def custom_query(query: AnalyticsQuery):
    """Execute a custom query against event data."""
    return await analytics_service.execute_query(query)
