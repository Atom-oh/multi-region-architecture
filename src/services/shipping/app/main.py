"""Shipping Service - FastAPI Application with Aurora PostgreSQL backend."""

import asyncio
import logging
import uuid
from datetime import datetime, date

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

from app.config import config

logger = logging.getLogger(__name__)

app = FastAPI(redirect_slashes=False, title="Shipping Service", version="1.0.0")

# PostgreSQL connection pool (initialized on startup)
_pg_pool = None

# Kafka consumer for order events - initialized on startup
_order_consumer = None
_consumer_task = None

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_tracing(config.service_name, app)
app.include_router(health_router)


def _row_to_shipment(row) -> dict:
    """Convert asyncpg Row to shipment dict."""
    return {
        "id": str(row["id"]),
        "order_id": str(row["order_id"]),
        "carrier": row["carrier"],
        "tracking_number": row["tracking_number"],
        "status": row["status"],
        "estimated_delivery": row["estimated_delivery"].isoformat() if row["estimated_delivery"] else None,
        "shipped_at": row["shipped_at"].isoformat() if row["shipped_at"] else None,
        "delivered_at": row["delivered_at"].isoformat() if row["delivered_at"] else None,
        "created_at": row["created_at"].isoformat() if row["created_at"] else None,
    }


@app.get("/")
async def root():
    return {"service": "shipping", "status": "running"}


@app.get("/api/v1/shipments")
async def list_shipments():
    """List all shipments."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT * FROM shipments ORDER BY created_at DESC LIMIT 20"
                )
                return [_row_to_shipment(row) for row in rows]
        except Exception as e:
            logger.warning(f"DB query failed: {e}")
    return []


@app.post("/api/v1/shipments")
async def create_shipment(shipment: dict):
    """Create a new shipment (DB with mock fallback)."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                shipment_id = uuid.uuid4()
                order_id = shipment.get("order_id")
                if order_id:
                    try:
                        order_id = uuid.UUID(order_id)
                    except ValueError:
                        order_id = uuid.uuid4()
                else:
                    order_id = uuid.uuid4()
                carrier = shipment.get("carrier", "CJ대한통운")
                tracking = f"MRM{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
                estimated = shipment.get("estimated_delivery")
                if estimated:
                    estimated = date.fromisoformat(estimated[:10]) if isinstance(estimated, str) else estimated

                row = await conn.fetchrow(
                    """
                    INSERT INTO shipments (id, order_id, carrier, tracking_number, status, estimated_delivery, created_at)
                    VALUES ($1, $2, $3, $4, $5, $6, NOW())
                    RETURNING *
                    """,
                    shipment_id, order_id, carrier, tracking, "preparing", estimated
                )
                result = _row_to_shipment(row)
                result["created"] = True
                result["message"] = "배송이 접수되었습니다"
                return result
        except Exception as e:
            logger.warning(f"DB insert failed, using mock: {e}")

    raise HTTPException(status_code=503, detail="배송 서비스가 일시적으로 불가합니다")


@app.get("/api/v1/shipments/{shipment_id}")
async def get_shipment(shipment_id: str):
    """Get shipment by ID."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                row = await conn.fetchrow(
                    "SELECT * FROM shipments WHERE id = $1::uuid", shipment_id
                )
                if row:
                    return _row_to_shipment(row)
        except Exception as e:
            logger.warning(f"DB query failed: {e}")
    raise HTTPException(status_code=404, detail="배송 정보를 찾을 수 없습니다")


@app.get("/api/v1/shipments/order/{order_id}")
async def get_shipments_by_order(order_id: str):
    """Get shipments by order ID."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT * FROM shipments WHERE order_id = $1::uuid ORDER BY created_at DESC",
                    order_id
                )
                if rows:
                    return [_row_to_shipment(row) for row in rows]
        except Exception as e:
            logger.warning(f"DB query failed: {e}")
    raise HTTPException(status_code=404, detail="주문에 대한 배송 정보를 찾을 수 없습니다")


@app.put("/api/v1/shipments/{shipment_id}/status")
async def update_status(shipment_id: str, status_update: dict):
    """Update shipment status."""
    if _pg_pool:
        try:
            new_status = status_update.get("status", "unknown")
            async with _pg_pool.acquire() as conn:
                result = await conn.execute(
                    "UPDATE shipments SET status = $1 WHERE id = $2::uuid",
                    new_status, shipment_id
                )
                if result != "UPDATE 0":
                    return {
                        "id": shipment_id,
                        "status": new_status,
                        "updated_at": datetime.utcnow().isoformat(),
                        "updated": True,
                        "message": "배송 상태가 업데이트되었습니다",
                    }
        except Exception as e:
            logger.warning(f"DB update failed: {e}")
    raise HTTPException(status_code=404, detail="배송 정보를 찾을 수 없습니다")


@app.get("/api/v1/shipments/track/{tracking_number}")
async def track_shipment(tracking_number: str):
    """Track shipment by tracking number."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                row = await conn.fetchrow(
                    "SELECT * FROM shipments WHERE tracking_number = $1", tracking_number
                )
                if row:
                    return _row_to_shipment(row)
        except Exception as e:
            logger.warning(f"DB query failed: {e}")
    raise HTTPException(status_code=404, detail="운송장 번호를 찾을 수 없습니다")


def _generate_dsql_token(hostname: str, region: str) -> str:
    import boto3
    client = boto3.client("dsql", region_name=region)
    return client.generate_db_connect_admin_auth_token(hostname, region)


@app.on_event("startup")
async def startup():
    global _pg_pool, _order_consumer, _consumer_task

    if config.db_host and config.db_host != "localhost":
        try:
            import asyncpg
            # Detect DSQL endpoint
            if ".dsql." in config.db_host:
                token = _generate_dsql_token(config.db_host, config.aws_region)
                _pg_pool = await asyncpg.create_pool(
                    host=config.db_host, port=5432,
                    database="postgres", user="admin", password=token,
                    ssl="require", min_size=1, max_size=5,
                    command_timeout=10, timeout=5,
                )
                logger.info(f"Connected to Aurora DSQL at {config.db_host}")
            else:
                _pg_pool = await asyncpg.create_pool(
                    host=config.db_host,
                    port=config.db_port if config.db_port != 27017 else 5432,
                    database=config.db_name or "mall",
                    user=config.db_user,
                    password=config.db_password,
                    ssl="require",
                    min_size=1,
                    max_size=5,
                    command_timeout=10, timeout=5,
                )
                logger.info(f"Connected to Aurora PostgreSQL at {config.db_host}")
        except Exception as e:
            logger.warning(f"PostgreSQL unavailable: {e}")
    else:
        logger.info("No DB_HOST configured, DB features disabled")

    # Initialize Kafka consumer for order events (graceful degradation)
    if config.kafka_brokers and config.kafka_brokers != "localhost:9092":
        try:
            from app.consumers.order_consumer import create_consumer
            _order_consumer = create_consumer(config.kafka_brokers)
            await _order_consumer.start()
            _consumer_task = asyncio.create_task(_order_consumer.consume())
            logger.info(f"Order consumer started for brokers: {config.kafka_brokers}")
        except Exception as e:
            logger.warning(f"Kafka unavailable: {e}, order consumer disabled")
    else:
        logger.info(f"No MSK brokers configured (KAFKA_BROKERS={config.kafka_brokers}), order consumer disabled")

    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _pg_pool, _order_consumer, _consumer_task

    if _pg_pool:
        await _pg_pool.close()
        logger.info("Closed Aurora PostgreSQL connection pool")

    if _consumer_task:
        _consumer_task.cancel()
        try:
            await _consumer_task
        except asyncio.CancelledError:
            pass

    if _order_consumer:
        try:
            await _order_consumer.stop()
            logger.info("Order consumer stopped")
        except Exception as e:
            logger.warning(f"Error stopping order consumer: {e}")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
