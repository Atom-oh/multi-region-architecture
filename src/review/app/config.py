"""Configuration for review service."""

from mall_common.config import ServiceConfig


class ReviewConfig(ServiceConfig):
    service_name: str = "review"
    db_name: str = "reviews"


config = ReviewConfig()
