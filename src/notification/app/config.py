"""Configuration for notification service."""

from mall_common.config import ServiceConfig


class NotificationConfig(ServiceConfig):
    service_name: str = "notification"


config = NotificationConfig()
