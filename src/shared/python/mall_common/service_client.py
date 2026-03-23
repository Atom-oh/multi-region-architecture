"""Shared inter-service HTTP client for MSA communication.

Uses httpx.AsyncClient with 2-second timeout. Failures return None/empty dict
for graceful degradation. OTel trace propagation is automatic via
HTTPXClientInstrumentor (already instrumented in tracing.py).
"""

import logging
import os

import httpx

logger = logging.getLogger(__name__)

PRODUCT_CATALOG_URL = os.getenv(
    "PRODUCT_CATALOG_URL",
    "http://product-catalog.core-services.svc.cluster.local:80",
)
USER_PROFILE_URL = os.getenv(
    "USER_PROFILE_URL",
    "http://user-profile.user-services.svc.cluster.local:80",
)
ORDER_URL = os.getenv(
    "ORDER_URL",
    "http://order.core-services.svc.cluster.local:80",
)

_TIMEOUT = httpx.Timeout(2.0, connect=1.0)


async def get_product(product_id: str) -> dict | None:
    """Fetch a single product from product-catalog service."""
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(f"{PRODUCT_CATALOG_URL}/api/v1/products/{product_id}")
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logger.warning("Failed to fetch product %s: %s", product_id, e)
    return None


async def get_products_by_ids(product_ids: list[str]) -> dict[str, dict]:
    """Fetch multiple products by ID. Returns {product_id: product_data} mapping."""
    result: dict[str, dict] = {}
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            for pid in product_ids:
                try:
                    resp = await client.get(f"{PRODUCT_CATALOG_URL}/api/v1/products/{pid}")
                    if resp.status_code == 200:
                        result[pid] = resp.json()
                except Exception as e:
                    logger.warning("Failed to fetch product %s: %s", pid, e)
    except Exception as e:
        logger.warning("Failed to create HTTP client for product batch: %s", e)
    return result


async def get_user_profile(user_id: str) -> dict | None:
    """Fetch user profile from user-profile service."""
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(f"{USER_PROFILE_URL}/api/v1/users/{user_id}")
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logger.warning("Failed to fetch user profile %s: %s", user_id, e)
    return None


async def get_order(order_id: str) -> dict | None:
    """Fetch order from order service."""
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(f"{ORDER_URL}/api/v1/orders/{order_id}")
            if resp.status_code == 200:
                return resp.json()
    except Exception as e:
        logger.warning("Failed to fetch order %s: %s", order_id, e)
    return None
