"""Analytics service for event aggregation and querying."""

import asyncio
import logging
import time
from collections import defaultdict
from datetime import datetime
from typing import Any, Optional
from uuid import uuid4

from ..models.analytics import (
    AnalyticsQuery,
    DashboardMetrics,
    EventRecord,
    QueryResult,
)
from .s3_service import S3Service

logger = logging.getLogger(__name__)


class AnalyticsService:
    def __init__(self):
        self.s3_service: Optional[S3Service] = None
        self.event_buffer: list[EventRecord] = []
        self.buffer_lock = asyncio.Lock()
        self.metrics = {
            "order_count": 0,
            "revenue": 0.0,
            "active_users": set(),
            "events_processed": 0,
            "events_by_topic": defaultdict(int),
        }
        self.metrics_lock = asyncio.Lock()

    def initialize_s3(self, bucket: str, prefix: str = "events/"):
        if bucket:
            self.s3_service = S3Service(bucket, prefix)
            logger.info(f"S3 service initialized with bucket: {bucket}")

    async def record_event(self, event: EventRecord) -> None:
        """Record an event for analytics."""
        async with self.buffer_lock:
            self.event_buffer.append(event)

        async with self.metrics_lock:
            self.metrics["events_processed"] += 1
            self.metrics["events_by_topic"][event.topic] += 1

            # Extract metrics from specific event types
            if event.topic == "orders" and event.payload:
                self.metrics["order_count"] += 1
                if "total" in event.payload:
                    self.metrics["revenue"] += float(event.payload.get("total", 0))
                if "user_id" in event.payload:
                    self.metrics["active_users"].add(event.payload["user_id"])

            if event.topic == "users" and event.payload:
                if "user_id" in event.payload:
                    self.metrics["active_users"].add(event.payload["user_id"])

        logger.debug(f"Recorded event: {event.id} from topic: {event.topic}")

    async def get_dashboard_metrics(self) -> DashboardMetrics:
        """Get aggregated dashboard metrics."""
        async with self.metrics_lock:
            return DashboardMetrics(
                order_count=self.metrics["order_count"],
                revenue=self.metrics["revenue"],
                active_users=len(self.metrics["active_users"]),
                events_processed=self.metrics["events_processed"],
                events_by_topic=dict(self.metrics["events_by_topic"]),
                last_updated=datetime.utcnow(),
            )

    async def get_events(
        self,
        topic: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 100,
    ) -> list[EventRecord]:
        """Get recent events with optional filtering."""
        async with self.buffer_lock:
            events = list(self.event_buffer)

        # Apply filters
        if topic:
            events = [e for e in events if e.topic == topic]

        if start_time:
            events = [e for e in events if e.timestamp >= start_time]

        if end_time:
            events = [e for e in events if e.timestamp <= end_time]

        # Sort by timestamp descending and limit
        events.sort(key=lambda e: e.timestamp, reverse=True)
        return events[:limit]

    async def execute_query(self, query: AnalyticsQuery) -> QueryResult:
        """Execute a custom analytics query."""
        start = time.time()

        async with self.buffer_lock:
            events = list(self.event_buffer)

        # Apply filters
        if query.topic:
            events = [e for e in events if e.topic == query.topic]

        if query.start_time:
            events = [e for e in events if e.timestamp >= query.start_time]

        if query.end_time:
            events = [e for e in events if e.timestamp <= query.end_time]

        result: Any = None
        count = len(events)

        if query.query_type == "count":
            if query.group_by:
                result = defaultdict(int)
                for e in events:
                    key = e.payload.get(query.group_by, "unknown") if e.payload else "unknown"
                    result[key] += 1
                result = dict(result)
            else:
                result = count

        elif query.query_type == "sum" and query.field:
            if query.group_by:
                result = defaultdict(float)
                for e in events:
                    if e.payload and query.field in e.payload:
                        key = e.payload.get(query.group_by, "unknown")
                        result[key] += float(e.payload[query.field])
                result = dict(result)
            else:
                result = sum(
                    float(e.payload.get(query.field, 0))
                    for e in events
                    if e.payload and query.field in e.payload
                )

        elif query.query_type == "avg" and query.field:
            values = [
                float(e.payload.get(query.field, 0))
                for e in events
                if e.payload and query.field in e.payload
            ]
            result = sum(values) / len(values) if values else 0

        elif query.query_type == "list":
            result = [e.model_dump() for e in events[:query.limit]]

        else:
            result = {"error": f"Unknown query type: {query.query_type}"}

        execution_time = (time.time() - start) * 1000

        return QueryResult(
            query_type=query.query_type,
            result=result,
            count=count,
            execution_time_ms=execution_time,
        )

    async def flush_to_s3(self) -> int:
        """Flush buffered events to S3."""
        if not self.s3_service:
            logger.debug("S3 not configured, skipping flush")
            return 0

        async with self.buffer_lock:
            if not self.event_buffer:
                return 0

            events_to_flush = self.event_buffer.copy()
            self.event_buffer.clear()

        count = await self.s3_service.write_events(events_to_flush)
        logger.info(f"Flushed {count} events to S3")
        return count


# Global instance
analytics_service = AnalyticsService()
