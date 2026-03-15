"""Configuration for wishlist service."""

from mall_common.config import ServiceConfig


class WishlistConfig(ServiceConfig):
    service_name: str = "wishlist"
    db_name: str = "wishlists"


config = WishlistConfig()
