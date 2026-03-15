"""Configuration for recommendation service."""

from mall_common.config import ServiceConfig


class RecommendationConfig(ServiceConfig):
    service_name: str = "recommendation"
    db_name: str = "recommendations"


config = RecommendationConfig()
