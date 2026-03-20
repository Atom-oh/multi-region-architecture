"""Notification Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="notification")
app = FastAPI(title="Notification Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock notifications
MOCK_NOTIFICATIONS = {
    "user-001": [
        {
            "id": "notif-001",
            "user_id": "user-001",
            "type": "order_shipped",
            "title": "Your order has shipped!",
            "message": "Order #ord-001 is on its way. Track it with tracking number 1Z999AA10123456784.",
            "read": False,
            "created_at": "2026-03-18T10:30:00Z",
        },
        {
            "id": "notif-002",
            "user_id": "user-001",
            "type": "price_drop",
            "title": "Price drop alert!",
            "message": "An item in your wishlist is now 20% off.",
            "read": True,
            "created_at": "2026-03-17T14:00:00Z",
        },
    ],
    "user-002": [
        {
            "id": "notif-003",
            "user_id": "user-002",
            "type": "order_delivered",
            "title": "Your order was delivered",
            "message": "Order #ord-002 has been delivered. Enjoy your purchase!",
            "read": False,
            "created_at": "2026-03-19T14:45:00Z",
        },
    ],
}


@app.get("/")
async def root():
    return {"service": "notification", "status": "running"}


@app.post("/api/v1/notifications")
async def create_notification(notification: dict):
    """Create a new notification (stub - returns acknowledgment)."""
    return {
        "id": f"notif-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "user_id": notification.get("user_id", "unknown"),
        "type": notification.get("type", "general"),
        "title": notification.get("title", "Notification"),
        "message": notification.get("message", ""),
        "read": False,
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
    }


@app.get("/api/v1/notifications/{user_id}")
async def get_notifications(user_id: str, unread_only: bool = False, limit: int = 20):
    """Get notifications for a user."""
    notifications = MOCK_NOTIFICATIONS.get(user_id, [])
    if unread_only:
        notifications = [n for n in notifications if not n["read"]]
    unread_count = len([n for n in MOCK_NOTIFICATIONS.get(user_id, []) if not n["read"]])
    return {
        "user_id": user_id,
        "notifications": notifications[:limit],
        "total": len(notifications),
        "unread_count": unread_count,
    }


@app.put("/api/v1/notifications/{notification_id}/read")
async def mark_read(notification_id: str):
    """Mark notification as read (stub - returns acknowledgment)."""
    return {
        "id": notification_id,
        "read": True,
        "read_at": datetime.utcnow().isoformat(),
        "updated": True,
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
