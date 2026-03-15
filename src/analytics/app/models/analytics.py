"""Analytics data models."""

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class DashboardMetrics(BaseModel):
    order_count: int = Field(description="Total number of orders")
    revenue: float = Field(description="Total revenue")
    active_users: int = Field(description="Number of active users")
    events_processed: int = Field(description="Total events processed")
    events_by_topic: dict[str, int] = Field(default_factory=dict, description="Event counts by topic")
    last_updated: datetime = Field(default_factory=datetime.utcnow)


class EventRecord(BaseModel):
    id: str
    topic: str
    key: Optional[str] = None
    payload: dict[str, Any]
    timestamp: datetime
    region: Optional[str] = None


class AnalyticsQuery(BaseModel):
    query_type: str = Field(description="Type of query: count, sum, avg, list")
    topic: Optional[str] = Field(None, description="Filter by topic")
    field: Optional[str] = Field(None, description="Field to aggregate on")
    start_time: Optional[datetime] = Field(None, description="Start of time range")
    end_time: Optional[datetime] = Field(None, description="End of time range")
    group_by: Optional[str] = Field(None, description="Field to group results by")
    limit: int = Field(100, ge=1, le=10000, description="Maximum results")


class QueryResult(BaseModel):
    query_type: str
    result: Any
    count: int
    execution_time_ms: float
