"""Valkey (Redis-compatible) cluster client using redis-py."""

import json
import ssl
from typing import Any

from redis.asyncio.cluster import RedisCluster

_client: RedisCluster | None = None


async def connect(host: str, port: int = 6379, use_tls: bool = True) -> RedisCluster:
    global _client
    ssl_context = ssl.create_default_context() if use_tls else None
    _client = RedisCluster(
        host=host,
        port=port,
        decode_responses=True,
        ssl=use_tls,
        ssl_context=ssl_context,
        read_from_replicas=True,  # Prefer same-AZ replicas for reads
        socket_timeout=3.0,
        socket_connect_timeout=2.0,
        retry_on_timeout=True,
    )
    await _client.ping()
    return _client


async def disconnect() -> None:
    global _client
    if _client:
        await _client.close()
        _client = None


def get_client() -> RedisCluster:
    if _client is None:
        raise RuntimeError("Valkey not connected. Call connect() first.")
    return _client


async def get_json(key: str) -> Any | None:
    if _client is None:
        return None
    val = await _client.get(key)
    if val is None:
        return None
    return json.loads(val)


async def set_json(key: str, value: Any, ttl_seconds: int | None = None) -> None:
    if _client is None:
        return
    data = json.dumps(value)
    if ttl_seconds:
        await _client.setex(key, ttl_seconds, data)
    else:
        await _client.set(key, data)


async def delete(key: str) -> None:
    if _client is None:
        return
    await _client.delete(key)


async def delete_pattern(pattern: str) -> None:
    """Delete all keys matching a glob pattern. Use sparingly."""
    if _client is None:
        return
    async for key in _client.scan_iter(match=pattern, count=100):
        await _client.delete(key)


async def ping() -> bool:
    if _client is None:
        return False
    try:
        return await _client.ping()
    except Exception:
        return False
