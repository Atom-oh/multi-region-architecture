"""Configuration for analytics service."""

from mall_common.config import ServiceConfig


class AnalyticsConfig(ServiceConfig):
    service_name: str = "analytics"
    s3_bucket: str = ""
    s3_prefix: str = "events/"
    flush_interval_seconds: int = 60
    flush_batch_size: int = 1000


settings = AnalyticsConfig()
