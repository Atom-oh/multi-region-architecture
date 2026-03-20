"""Shipping Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="shipping")
app = FastAPI(title="Shipping Service", version="1.0.0")

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


@app.get("/")
async def root():
    return {"service": "shipping", "status": "running"}


@app.post("/api/v1/shipments")
async def create_shipment(shipment: dict):
    """Create a new shipment (stub - returns mock response)."""
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
    """Get shipment by ID."""
    if shipment_id in MOCK_SHIPMENTS:
        return MOCK_SHIPMENTS[shipment_id]
    raise HTTPException(status_code=404, detail="배송 정보를 찾을 수 없습니다")


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
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
