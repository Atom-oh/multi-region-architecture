"""Shipping Service - FastAPI Application with Aurora PostgreSQL backend."""

import logging
import uuid
from datetime import datetime, date

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

logger = logging.getLogger(__name__)

config = ServiceConfig(service_name="shipping")
app = FastAPI(title="Shipping Service", version="1.0.0")

# PostgreSQL connection pool (initialized on startup)
_pg_pool = None

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

# Mock shipments - consistent with shared order IDs
MOCK_SHIPMENTS = {
    "SHIP-001": {
        "id": "SHIP-001",
        "order_id": "ORD-001",
        "user_id": "USR-001",
        "tracking_number": "CJ1234567890123",
        "carrier": "CJ대한통운",
        "carrier_code": "CJ",
        "status": "delivered",
        "status_display": "배송완료",
        "estimated_delivery": "2026-03-18T18:00:00Z",
        "actual_delivery": "2026-03-18T14:32:00Z",
        "origin": {
            "name": "Multi-Region Mall 물류센터",
            "address": "서울특별시 강남구 테헤란로 123",
            "phone": "02-1234-5678",
        },
        "destination": {
            "name": "김민수",
            "address": "서울특별시 강남구 테헤란로 123 멀티리전타워 15층",
            "phone": "010-1234-5678",
        },
        "events": [
            {"status": "delivered", "status_display": "배송완료", "location": "서울 강남구", "timestamp": "2026-03-18T14:32:00Z", "description": "고객님께 배송 완료되었습니다."},
            {"status": "out_for_delivery", "status_display": "배송출발", "location": "강남 대리점", "timestamp": "2026-03-18T08:15:00Z", "description": "배송 출발하였습니다."},
            {"status": "in_transit", "status_display": "배송중", "location": "서울 HUB", "timestamp": "2026-03-17T22:30:00Z", "description": "서울 HUB에서 상품을 인수하였습니다."},
            {"status": "shipped", "status_display": "발송완료", "location": "강남 물류센터", "timestamp": "2026-03-17T14:00:00Z", "description": "상품이 발송되었습니다."},
            {"status": "picked_up", "status_display": "집하완료", "location": "강남 물류센터", "timestamp": "2026-03-17T10:00:00Z", "description": "상품을 집하하였습니다."},
        ],
        "created_at": "2026-03-17T09:00:00Z",
    },
    "SHIP-002": {
        "id": "SHIP-002",
        "order_id": "ORD-002",
        "user_id": "USR-002",
        "tracking_number": "HANJIN9876543210",
        "carrier": "한진택배",
        "carrier_code": "HANJIN",
        "status": "in_transit",
        "status_display": "배송중",
        "estimated_delivery": "2026-03-21T18:00:00Z",
        "actual_delivery": None,
        "origin": {
            "name": "Multi-Region Mall 물류센터",
            "address": "서울특별시 강남구 테헤란로 123",
            "phone": "02-1234-5678",
        },
        "destination": {
            "name": "이서연",
            "address": "서울특별시 서초구 강남대로 456 힐스테이트 1203호",
            "phone": "010-9876-5432",
        },
        "events": [
            {"status": "in_transit", "status_display": "배송중", "location": "용인 HUB", "timestamp": "2026-03-20T06:00:00Z", "description": "용인 HUB에서 상품을 인수하였습니다."},
            {"status": "shipped", "status_display": "발송완료", "location": "강남 물류센터", "timestamp": "2026-03-19T16:00:00Z", "description": "상품이 발송되었습니다."},
            {"status": "picked_up", "status_display": "집하완료", "location": "강남 물류센터", "timestamp": "2026-03-19T14:30:00Z", "description": "상품을 집하하였습니다."},
        ],
        "created_at": "2026-03-19T14:00:00Z",
    },
    "SHIP-003": {
        "id": "SHIP-003",
        "order_id": "ORD-003",
        "user_id": "USR-003",
        "tracking_number": "LOTTE5555666677",
        "carrier": "롯데택배",
        "carrier_code": "LOTTE",
        "status": "processing",
        "status_display": "상품준비중",
        "estimated_delivery": "2026-03-23T18:00:00Z",
        "actual_delivery": None,
        "origin": {
            "name": "Multi-Region Mall 부산센터",
            "address": "부산광역시 해운대구 센텀로 100",
            "phone": "051-1234-5678",
        },
        "destination": {
            "name": "박지훈",
            "address": "부산광역시 해운대구 해운대로 789 마린시티 2501호",
            "phone": "010-5555-7777",
        },
        "events": [
            {"status": "processing", "status_display": "상품준비중", "location": "부산 물류센터", "timestamp": "2026-03-20T10:00:00Z", "description": "상품을 포장하고 있습니다."},
        ],
        "created_at": "2026-03-20T09:00:00Z",
    },
}

TRACKING_MAP = {
    "CJ1234567890123": "SHIP-001",
    "HANJIN9876543210": "SHIP-002",
    "LOTTE5555666677": "SHIP-003",
}


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
    """List all shipments (DB with mock fallback)."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT * FROM shipments ORDER BY created_at DESC LIMIT 20"
                )
                return [_row_to_shipment(row) for row in rows]
        except Exception as e:
            logger.warning(f"DB query failed, using mock: {e}")
    return list(MOCK_SHIPMENTS.values())


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

    # Mock fallback
    shipment_id = f"SHIP-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    tracking = f"MRM{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    return {
        "id": shipment_id,
        "order_id": shipment.get("order_id", "unknown"),
        "tracking_number": tracking,
        "carrier": shipment.get("carrier", "CJ대한통운"),
        "carrier_code": "CJ",
        "status": "pending",
        "status_display": "접수대기",
        "estimated_delivery": "2026-03-25T18:00:00Z",
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
        "message": "배송이 접수되었습니다",
    }


@app.get("/api/v1/shipments/{shipment_id}")
async def get_shipment(shipment_id: str):
    """Get shipment by ID (DB with mock fallback)."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                row = await conn.fetchrow(
                    "SELECT * FROM shipments WHERE id::text = $1", shipment_id
                )
                if row:
                    return _row_to_shipment(row)
        except Exception as e:
            logger.warning(f"DB query failed, using mock: {e}")

    # Mock fallback
    if shipment_id in MOCK_SHIPMENTS:
        return MOCK_SHIPMENTS[shipment_id]
    raise HTTPException(status_code=404, detail="배송 정보를 찾을 수 없습니다")


@app.get("/api/v1/shipments/order/{order_id}")
async def get_shipments_by_order(order_id: str):
    """Get shipments by order ID (DB with mock fallback)."""
    if _pg_pool:
        try:
            async with _pg_pool.acquire() as conn:
                rows = await conn.fetch(
                    "SELECT * FROM shipments WHERE order_id::text = $1 ORDER BY created_at DESC",
                    order_id
                )
                if rows:
                    return [_row_to_shipment(row) for row in rows]
        except Exception as e:
            logger.warning(f"DB query failed, using mock: {e}")

    # Mock fallback
    results = [s for s in MOCK_SHIPMENTS.values() if s.get("order_id") == order_id]
    if results:
        return results
    raise HTTPException(status_code=404, detail="주문에 대한 배송 정보를 찾을 수 없습니다")


@app.put("/api/v1/shipments/{shipment_id}/status")
async def update_status(shipment_id: str, status_update: dict):
    """Update shipment status (stub - returns acknowledgment)."""
    if shipment_id not in MOCK_SHIPMENTS:
        raise HTTPException(status_code=404, detail="배송 정보를 찾을 수 없습니다")
    return {
        "id": shipment_id,
        "status": status_update.get("status", "unknown"),
        "updated_at": datetime.utcnow().isoformat(),
        "updated": True,
        "message": "배송 상태가 업데이트되었습니다",
    }


@app.get("/api/v1/shipments/track/{tracking_number}")
async def track_shipment(tracking_number: str):
    """Track shipment by tracking number."""
    if tracking_number in TRACKING_MAP:
        return MOCK_SHIPMENTS[TRACKING_MAP[tracking_number]]
    raise HTTPException(status_code=404, detail="운송장 번호를 찾을 수 없습니다")


@app.on_event("startup")
async def startup():
    global _pg_pool
    if config.db_host and config.db_host != "localhost":
        try:
            import asyncpg
            _pg_pool = await asyncpg.create_pool(
                host=config.db_host,
                port=config.db_port if config.db_port != 27017 else 5432,
                database=config.db_name or "mall",
                user=config.db_user,
                password=config.db_password,
                ssl="require",
                min_size=1,
                max_size=5,
            )
            logger.info(f"Connected to Aurora PostgreSQL at {config.db_host}")
        except Exception as e:
            logger.warning(f"Aurora PostgreSQL unavailable, using mock data: {e}")
    else:
        logger.info("No DB_HOST configured, using mock data")
    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    global _pg_pool
    if _pg_pool:
        await _pg_pool.close()
        logger.info("Closed Aurora PostgreSQL connection pool")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
