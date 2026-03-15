"""Notification API routes."""

from fastapi import APIRouter

from app.models.notification import NotificationListResponse, NotificationRequest, NotificationResponse
from app.services.notification_service import notification_service

router = APIRouter(prefix="/api/v1/notifications", tags=["notifications"])


@router.get("/{user_id}", response_model=NotificationListResponse)
async def get_notifications(user_id: str, limit: int = 50):
    """Get recent notifications for a user."""
    notifications = await notification_service.get_user_notifications(user_id, limit)
    return NotificationListResponse(notifications=notifications, total=len(notifications))


@router.post("/send", response_model=NotificationResponse)
async def send_notification(request: NotificationRequest):
    """Manually send a notification."""
    return await notification_service.send_notification(request)
