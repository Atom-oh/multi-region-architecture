"""Health check router re-export."""

from mall_common.health import router, set_ready, set_started

__all__ = ["router", "set_ready", "set_started"]
