"""Region-aware middleware for FastAPI services."""

import httpx
from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from .config import ServiceConfig


class RegionWriteMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, config: ServiceConfig):
        super().__init__(app)
        self.config = config
        self.client = httpx.AsyncClient(timeout=30.0)

    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        if self.config.is_primary:
            return await call_next(request)

        if request.method in ("POST", "PUT", "PATCH", "DELETE") and self.config.primary_host:
            return await self._forward_to_primary(request)

        return await call_next(request)

    async def _forward_to_primary(self, request: Request) -> Response:
        target_url = f"{self.config.primary_host}{request.url.path}"
        if request.url.query:
            target_url += f"?{request.url.query}"

        body = await request.body()
        headers = dict(request.headers)
        headers["x-forwarded-from-region"] = self.config.aws_region

        try:
            resp = await self.client.request(
                method=request.method,
                url=target_url,
                content=body,
                headers=headers,
            )
            return Response(
                content=resp.content,
                status_code=resp.status_code,
                headers=dict(resp.headers),
            )
        except httpx.RequestError:
            return Response(
                content='{"error":"failed to forward to primary"}',
                status_code=502,
                media_type="application/json",
            )
