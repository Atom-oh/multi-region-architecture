"""Valkey (Redis-compatible) cluster client using redis-py."""

import json
import logging
import ssl
from typing import Any

from redis.asyncio.cluster import RedisCluster

logger = logging.getLogger(__name__)

_client: RedisCluster | None = None
_write_client: RedisCluster | None = None


def _make_client(host: str, port: int, use_tls: bool, read_from_replicas: bool) -> RedisCluster:
    ssl_context = ssl.create_default_context() if use_tls else None
    return RedisCluster(
        host=host,
        port=port,
        decode_responses=True,
        ssl=use_tls,
        ssl_context=ssl_context,
        read_from_replicas=read_from_replicas,
        socket_timeout=3.0,
        socket_connect_timeout=2.0,
        retry_on_timeout=True,
    )


async def connect(host: str, port: int = 6379, use_tls: bool = True) -> RedisCluster:
    global _client
    _client = _make_client(host, port, use_tls, read_from_replicas=True)
    await _client.ping()
    return _client


async def connect_writer(host: str, port: int = 6379, use_tls: bool = True) -> RedisCluster:
    global _write_client
    _write_client = _make_client(host, port, use_tls, read_from_replicas=False)
    await _write_client.ping()
    return _write_client


async def disconnect() -> None:
    global _client, _write_client
    if _client:
        await _client.close()
        _client = None
    if _write_client:
        await _write_client.close()
        _write_client = None


def get_client() -> RedisCluster:
    if _client is None:
        raise RuntimeError("Valkey not connected. Call connect() first.")
    return _client


def get_write_client() -> RedisCluster:
    if _write_client is not None:
        return _write_client
    return get_client()


async def get_json(key: str) -> Any | None:
    if _client is None:
        return None
    val = await _client.get(key)
    if val is None:
        return None
    return json.loads(val)


async def set_json(key: str, value: Any, ttl_seconds: int | None = None) -> None:
    wc = _write_client or _client
    if wc is None:
        return
    data = json.dumps(value)
    if ttl_seconds:
        await wc.setex(key, ttl_seconds, data)
    else:
        await wc.set(key, data)


async def delete(key: str) -> None:
    wc = _write_client or _client
    if wc is None:
        return
    await wc.delete(key)


async def delete_pattern(pattern: str) -> None:
    """Delete all keys matching a glob pattern. Use sparingly."""
    wc = _write_client or _client
    if wc is None:
        return
    async for key in wc.scan_iter(match=pattern, count=100):
        await wc.delete(key)


async def ping() -> bool:
    if _client is None:
        return False
    try:
        return await _client.ping()
    except Exception:
        return False
