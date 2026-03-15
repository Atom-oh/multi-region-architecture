"""Configuration for user-profile service."""

from mall_common.config import ServiceConfig


class ProfileConfig(ServiceConfig):
    service_name: str = "user-profile"
    db_name: str = "user_profiles"


config = ProfileConfig()
