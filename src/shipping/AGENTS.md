<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# shipping/

## Purpose
Python FastAPI shipping service managing shipment creation, carrier integration, tracking updates, and delivery notifications. Consumes order events to auto-create shipments.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/shipment.py` | Pydantic shipment models |
| `app/repositories/shipment_repo.py` | DocumentDB repository |
| `app/services/shipment_service.py` | Shipment business logic |
| `app/routers/shipments.py` | Shipment REST endpoints |
| `app/routers/health.py` | Health check endpoint |
| `app/consumers/order_consumer.py` | Kafka order event consumer |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/repositories/` | DocumentDB access |
| `app/services/` | Business logic |
| `app/routers/` | FastAPI route handlers |
| `app/consumers/` | Kafka event consumers |

## For AI Agents

### Working In This Directory
- Shipment status: CREATED, PICKED_UP, IN_TRANSIT, DELIVERED
- Consumes order.shipped events to create shipments
- Tracking updates via webhook from carriers

### Common Patterns
```python
# Kafka consumer pattern
async def consume_order_events():
    async for msg in consumer:
        event = json.loads(msg.value)
        await shipment_service.create_from_order(event)
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, DocumentDB, Kafka
### External
- fastapi
- uvicorn
- aiokafka
- motor

<!-- MANUAL: -->
