"""Shipping Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="shipping")
app = FastAPI(title="Shipping Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock shipments
MOCK_SHIPMENTS = {
    "ship-001": {
        "id": "ship-001",
        "order_id": "ord-001",
        "tracking_number": "1Z999AA10123456784",
        "carrier": "UPS",
        "status": "in_transit",
        "estimated_delivery": "2026-03-22T18:00:00Z",
        "origin": {"city": "Seattle", "state": "WA", "country": "US"},
        "destination": {"city": "Portland", "state": "OR", "country": "US"},
        "events": [
            {"status": "picked_up", "location": "Seattle, WA", "timestamp": "2026-03-18T10:00:00Z"},
            {"status": "in_transit", "location": "Tacoma, WA", "timestamp": "2026-03-19T08:30:00Z"},
        ],
        "created_at": "2026-03-18T09:00:00Z",
    },
    "ship-002": {
        "id": "ship-002",
        "order_id": "ord-002",
        "tracking_number": "9400111899223100001234",
        "carrier": "USPS",
        "status": "delivered",
        "estimated_delivery": "2026-03-19T17:00:00Z",
        "origin": {"city": "Los Angeles", "state": "CA", "country": "US"},
        "destination": {"city": "San Francisco", "state": "CA", "country": "US"},
        "events": [
            {"status": "picked_up", "location": "Los Angeles, CA", "timestamp": "2026-03-17T14:00:00Z"},
            {"status": "in_transit", "location": "Bakersfield, CA", "timestamp": "2026-03-18T06:00:00Z"},
            {"status": "out_for_delivery", "location": "San Francisco, CA", "timestamp": "2026-03-19T08:00:00Z"},
            {"status": "delivered", "location": "San Francisco, CA", "timestamp": "2026-03-19T14:30:00Z"},
        ],
        "created_at": "2026-03-17T13:00:00Z",
    },
}

TRACKING_MAP = {
    "1Z999AA10123456784": "ship-001",
    "9400111899223100001234": "ship-002",
}


@app.get("/")
async def root():
    return {"service": "shipping", "status": "running"}


@app.post("/api/v1/shipments")
async def create_shipment(shipment: dict):
    """Create a new shipment (stub - returns mock response)."""
    shipment_id = f"ship-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    tracking = f"TRK{datetime.utcnow().strftime('%Y%m%d%H%M%S')}"
    return {
        "id": shipment_id,
        "order_id": shipment.get("order_id", "unknown"),
        "tracking_number": tracking,
        "carrier": shipment.get("carrier", "UPS"),
        "status": "pending",
        "estimated_delivery": "2026-03-25T18:00:00Z",
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
    }


@app.get("/api/v1/shipments/{shipment_id}")
async def get_shipment(shipment_id: str):
    """Get shipment by ID."""
    if shipment_id in MOCK_SHIPMENTS:
        return MOCK_SHIPMENTS[shipment_id]
    raise HTTPException(status_code=404, detail="Shipment not found")


@app.put("/api/v1/shipments/{shipment_id}/status")
async def update_status(shipment_id: str, status_update: dict):
    """Update shipment status (stub - returns acknowledgment)."""
    if shipment_id not in MOCK_SHIPMENTS:
        raise HTTPException(status_code=404, detail="Shipment not found")
    return {
        "id": shipment_id,
        "status": status_update.get("status", "unknown"),
        "updated_at": datetime.utcnow().isoformat(),
        "updated": True,
    }


@app.get("/api/v1/shipments/track/{tracking_number}")
async def track_shipment(tracking_number: str):
    """Track shipment by tracking number."""
    if tracking_number in TRACKING_MAP:
        return MOCK_SHIPMENTS[TRACKING_MAP[tracking_number]]
    raise HTTPException(status_code=404, detail="Tracking number not found")


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
