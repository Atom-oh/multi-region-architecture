"""DocumentDB (MongoDB-compatible) client using Motor."""

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

_client: AsyncIOMotorClient | None = None
_db: AsyncIOMotorDatabase | None = None

_write_client: AsyncIOMotorClient | None = None
_write_db: AsyncIOMotorDatabase | None = None

_POOL_OPTS = dict(
    maxPoolSize=50,
    minPoolSize=5,
    maxIdleTimeMS=300000,
    waitQueueTimeoutMS=5000,
    serverSelectionTimeoutMS=5000,
    socketTimeoutMS=10000,
    connectTimeoutMS=5000,
)


async def connect(uri: str, db_name: str) -> AsyncIOMotorDatabase:
    global _client, _db
    _client = AsyncIOMotorClient(uri, **_POOL_OPTS)
    _db = _client[db_name]
    return _db


async def connect_writer(uri: str, db_name: str) -> AsyncIOMotorDatabase:
    global _write_client, _write_db
    _write_client = AsyncIOMotorClient(uri, **_POOL_OPTS)
    _write_db = _write_client[db_name]
    return _write_db


async def disconnect() -> None:
    global _client, _db, _write_client, _write_db
    if _client:
        _client.close()
        _client = None
        _db = None
    if _write_client:
        _write_client.close()
        _write_client = None
        _write_db = None


def get_db() -> AsyncIOMotorDatabase:
    if _db is None:
        raise RuntimeError("DocumentDB not connected. Call connect() first.")
    return _db


def get_write_db() -> AsyncIOMotorDatabase:
    if _write_db is not None:
        return _write_db
    return get_db()


async def ping() -> bool:
    if _client is None:
        return False
    try:
        await _client.admin.command("ping")
        return True
    except Exception:
        return False
