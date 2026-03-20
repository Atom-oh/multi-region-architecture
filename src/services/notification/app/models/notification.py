"""Pydantic models for notification service."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class NotificationChannel(str, Enum):
    EMAIL = "EMAIL"
    SMS = "SMS"
    PUSH = "PUSH"


class NotificationStatus(str, Enum):
    PENDING = "PENDING"
    SENT = "SENT"
    FAILED = "FAILED"


class Notification(BaseModel):
    id: str
    user_id: str
    channel: NotificationChannel
    subject: str
    message: str
    status: NotificationStatus = NotificationStatus.PENDING
    created_at: datetime = Field(default_factory=datetime.utcnow)
    sent_at: Optional[datetime] = None
    metadata: Optional[dict] = None


class NotificationRequest(BaseModel):
    user_id: str
    channel: NotificationChannel
    subject: str
    message: str
    metadata: Optional[dict] = None


class NotificationResponse(BaseModel):
    id: str
    user_id: str
    channel: NotificationChannel
    status: NotificationStatus
    created_at: datetime


class NotificationListResponse(BaseModel):
    notifications: list[Notification]
    total: int
