"""Valkey (Redis-compatible) client using redis-py.

production-elasticache-ap-northeast-2 is a standard (non-cluster-mode)
replication group — `aws elasticache describe-replication-groups` reports
ClusterEnabled=false and a single "master."-prefixed primary endpoint, no
configuration endpoint. redis.asyncio.cluster.RedisCluster expects a
cluster-mode deployment (it issues CLUSTER SLOTS on connect) and simply
cannot connect to this endpoint. Reader/writer separation here is done at
the application layer by pointing connect()/connect_writer() at different
hosts (CACHE_HOST vs CACHE_WRITE_HOST), not via RedisCluster's built-in
replica routing.
"""

import json
import logging
from typing import Any

from redis.asyncio import Redis

logger = logging.getLogger(__name__)

_client: Redis | None = None
_write_client: Redis | None = None


def _make_client(host: str, port: int, use_tls: bool) -> Redis:
    return Redis(
        host=host,
        port=port,
        decode_responses=True,
        ssl=use_tls,
        socket_timeout=3.0,
        socket_connect_timeout=2.0,
    )


async def connect(host: str, port: int = 6379, use_tls: bool = True) -> Redis:
    global _client
    _client = _make_client(host, port, use_tls)
    await _client.ping()
    return _client


async def connect_writer(host: str, port: int = 6379, use_tls: bool = True) -> Redis:
    global _write_client
    _write_client = _make_client(host, port, use_tls)
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


def get_client() -> Redis:
    if _client is None:
        raise RuntimeError("Valkey not connected. Call connect() first.")
    return _client


def get_write_client() -> Redis:
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
