<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# analytics/

## Purpose
Python FastAPI analytics service consuming all platform events for aggregation, reporting, and data lake storage in S3. Provides real-time metrics and historical analytics APIs.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/analytics.py` | Pydantic analytics models |
| `app/services/analytics_service.py` | Analytics aggregation logic |
| `app/services/s3_service.py` | S3 data lake operations |
| `app/routers/analytics.py` | Analytics REST endpoints |
| `app/routers/health.py` | Health check endpoint |
| `app/consumers/all_events_consumer.py` | Multi-topic Kafka consumer |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/services/` | Analytics and S3 services |
| `app/routers/` | FastAPI route handlers |
| `app/consumers/` | Kafka event consumers |

## For AI Agents

### Working In This Directory
- Consumes from multiple Kafka topics (orders, payments, users, etc.)
- Real-time metrics in Valkey, historical in S3
- S3 path format: `s3://bucket/analytics/{year}/{month}/{day}/`

### Common Patterns
```python
# Multi-topic consumer
async def consume_all_events():
    consumer.subscribe(["orders", "payments", "users", "products"])
    async for msg in consumer:
        await process_event(msg.topic, msg.value)

# S3 batch upload
async def flush_to_s3(events: List[dict]):
    key = f"analytics/{date.today()}/{uuid4()}.json"
    await s3.put_object(Bucket=bucket, Key=key, Body=json.dumps(events))
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, Kafka, Valkey
### External
- fastapi
- uvicorn
- aiokafka
- aiobotocore (async S3)

<!-- MANUAL: -->
