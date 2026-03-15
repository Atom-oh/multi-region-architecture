"""Health check router for FastAPI services."""

from fastapi import APIRouter

router = APIRouter(prefix="/health", tags=["health"])

_ready = False
_started = False


def set_ready(ready: bool) -> None:
    global _ready
    _ready = ready


def set_started(started: bool) -> None:
    global _started
    _started = started


@router.get("/ready")
async def readiness():
    if _ready:
        return {"status": "ready"}
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=503, content={"status": "not_ready"})


@router.get("/live")
async def liveness():
    return {"status": "alive"}


@router.get("/startup")
async def startup():
    if _started:
        return {"status": "started"}
    from fastapi.responses import JSONResponse
    return JSONResponse(status_code=503, content={"status": "starting"})
