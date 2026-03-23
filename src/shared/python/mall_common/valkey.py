"""Valkey (Redis-compatible) client using redis-py."""

import json
from typing import Any

import redis.asyncio as aioredis

_client: aioredis.Redis | None = None


async def connect(host: str, port: int = 6379) -> aioredis.Redis:
    global _client
    _client = aioredis.Redis(host=host, port=port, decode_responses=True)
    await _client.ping()
    return _client


async def disconnect() -> None:
    global _client
    if _client:
        await _client.close()
        _client = None


def get_client() -> aioredis.Redis:
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


async def ping() -> bool:
    if _client is None:
        return False
    try:
        return await _client.ping()
    except Exception:
        return False
