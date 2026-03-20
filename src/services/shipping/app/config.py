"""Shipping service configuration."""

from mall_common.config import ServiceConfig


class ShippingConfig(ServiceConfig):
    service_name: str = "shipping"
    db_name: str = "shipping"


config = ShippingConfig()
