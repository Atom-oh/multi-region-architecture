"""Product catalog service configuration."""

from mall_common.config import ServiceConfig


class ProductCatalogConfig(ServiceConfig):
    service_name: str = "product-catalog"
    db_name: str = "product_catalog"


config = ProductCatalogConfig()
