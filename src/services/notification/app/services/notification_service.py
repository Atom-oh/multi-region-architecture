"""Notification dispatch service."""

import logging
import uuid
from collections import deque
from datetime import datetime
from typing import Deque

from app.models.notification import (
    Notification,
    NotificationChannel,
    NotificationRequest,
    NotificationResponse,
    NotificationStatus,
)

logger = logging.getLogger(__name__)

MAX_NOTIFICATIONS_PER_USER = 100


class NotificationService:
    def __init__(self):
        self._notifications: dict[str, Deque[Notification]] = {}

    async def send_notification(self, request: NotificationRequest) -> NotificationResponse:
        """Send a notification to a user."""
        notification_id = str(uuid.uuid4())

        notification = Notification(
            id=notification_id,
            user_id=request.user_id,
            channel=request.channel,
            subject=request.subject,
            message=request.message,
            metadata=request.metadata,
            status=NotificationStatus.PENDING,
            created_at=datetime.utcnow(),
        )

        success = await self._dispatch(notification)

        notification.status = NotificationStatus.SENT if success else NotificationStatus.FAILED
        if success:
            notification.sent_at = datetime.utcnow()

        self._store_notification(notification)

        return NotificationResponse(
            id=notification.id,
            user_id=notification.user_id,
            channel=notification.channel,
            status=notification.status,
            created_at=notification.created_at,
        )

    async def get_user_notifications(self, user_id: str, limit: int = 50) -> list[Notification]:
        """Get recent notifications for a user."""
        if user_id not in self._notifications:
            return []

        notifications = list(self._notifications[user_id])
        return notifications[:limit]

    async def process_order_event(self, event: dict) -> None:
        """Process order events and send notifications."""
        event_type = event.get("type", "")
        user_id = event.get("user_id")
        order_id = event.get("order_id")

        if not user_id:
            logger.warning("Order event missing user_id: %s", event)
            return

        subject = ""
        message = ""

        if event_type == "order.created":
            subject = "Order Confirmed"
            message = f"Your order {order_id} has been confirmed."
        elif event_type == "order.cancelled":
            subject = "Order Cancelled"
            message = f"Your order {order_id} has been cancelled."
        elif event_type == "order.shipped":
            subject = "Order Shipped"
            message = f"Your order {order_id} has been shipped."

        if subject:
            request = NotificationRequest(
                user_id=user_id,
                channel=NotificationChannel.EMAIL,
                subject=subject,
                message=message,
                metadata={"order_id": order_id},
            )
            await self.send_notification(request)

    async def process_payment_event(self, event: dict) -> None:
        """Process payment events and send notifications."""
        event_type = event.get("type", "")
        user_id = event.get("user_id")
        payment_id = event.get("payment_id")

        if not user_id:
            logger.warning("Payment event missing user_id: %s", event)
            return

        subject = ""
        message = ""

        if event_type == "payment.completed":
            subject = "Payment Successful"
            message = f"Your payment {payment_id} was successful."
        elif event_type == "payment.failed":
            subject = "Payment Failed"
            message = f"Your payment {payment_id} failed. Please try again."

        if subject:
            request = NotificationRequest(
                user_id=user_id,
                channel=NotificationChannel.EMAIL,
                subject=subject,
                message=message,
                metadata={"payment_id": payment_id},
            )
            await self.send_notification(request)

    async def process_shipping_event(self, event: dict) -> None:
        """Process shipping events and send notifications."""
        event_type = event.get("type", "")
        user_id = event.get("user_id")
        shipment_id = event.get("shipment_id")
        tracking_number = event.get("tracking_number", "")

        if not user_id:
            logger.warning("Shipping event missing user_id: %s", event)
            return

        subject = ""
        message = ""

        if event_type == "shipping.shipped":
            subject = "Your Order Has Shipped"
            message = f"Shipment {shipment_id} is on its way. Tracking: {tracking_number}"
        elif event_type == "shipping.delivered":
            subject = "Order Delivered"
            message = f"Shipment {shipment_id} has been delivered."
        elif event_type == "shipping.out_for_delivery":
            subject = "Out for Delivery"
            message = f"Shipment {shipment_id} is out for delivery today."

        if subject:
            request = NotificationRequest(
                user_id=user_id,
                channel=NotificationChannel.PUSH,
                subject=subject,
                message=message,
                metadata={"shipment_id": shipment_id, "tracking_number": tracking_number},
            )
            await self.send_notification(request)

    async def _dispatch(self, notification: Notification) -> bool:
        """Dispatch notification to the appropriate channel."""
        try:
            if notification.channel == NotificationChannel.EMAIL:
                return await self._send_email(notification)
            elif notification.channel == NotificationChannel.SMS:
                return await self._send_sms(notification)
            elif notification.channel == NotificationChannel.PUSH:
                return await self._send_push(notification)
            return False
        except Exception:
            logger.exception("Failed to dispatch notification %s", notification.id)
            return False

    async def _send_email(self, notification: Notification) -> bool:
        """Send email notification (stub)."""
        logger.info(
            "EMAIL -> user=%s subject='%s' message='%s'",
            notification.user_id,
            notification.subject,
            notification.message[:50],
        )
        return True

    async def _send_sms(self, notification: Notification) -> bool:
        """Send SMS notification (stub)."""
        logger.info(
            "SMS -> user=%s message='%s'",
            notification.user_id,
            notification.message[:50],
        )
        return True

    async def _send_push(self, notification: Notification) -> bool:
        """Send push notification (stub)."""
        logger.info(
            "PUSH -> user=%s subject='%s' message='%s'",
            notification.user_id,
            notification.subject,
            notification.message[:50],
        )
        return True

    def _store_notification(self, notification: Notification) -> None:
        """Store notification in memory for retrieval."""
        if notification.user_id not in self._notifications:
            self._notifications[notification.user_id] = deque(maxlen=MAX_NOTIFICATIONS_PER_USER)

        self._notifications[notification.user_id].appendleft(notification)


notification_service = NotificationService()
