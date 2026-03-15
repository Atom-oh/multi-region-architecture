"""Health router re-export from shared library."""

from mall_common.health import router, set_ready, set_started

__all__ = ["router", "set_ready", "set_started"]
