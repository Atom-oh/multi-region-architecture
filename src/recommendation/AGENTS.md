<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# recommendation/

## Purpose
Python FastAPI recommendation service providing personalized product recommendations based on user activity, purchase history, and collaborative filtering. Consumes activity events to update models.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/recommendation.py` | Pydantic models |
| `app/repositories/recommendation_repo.py` | DocumentDB repository |
| `app/services/recommendation_service.py` | Recommendation logic |
| `app/routers/recommendations.py` | REST endpoints |
| `app/routers/health.py` | Health check endpoint |
| `app/consumers/activity_consumer.py` | Kafka activity consumer |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/repositories/` | DocumentDB access |
| `app/services/` | Recommendation algorithms |
| `app/routers/` | FastAPI route handlers |
| `app/consumers/` | Kafka event consumers |

## For AI Agents

### Working In This Directory
- Recommendation types: similar, personalized, trending
- Activity events update user preference vectors
- Results cached in Valkey with TTL

### Common Patterns
```python
# Recommendation with caching
async def get_recommendations(user_id: str, limit: int = 10):
    cached = await valkey.get(f"recs:{user_id}")
    if cached:
        return json.loads(cached)
    recs = await compute_recommendations(user_id, limit)
    await valkey.setex(f"recs:{user_id}", 3600, json.dumps(recs))
    return recs
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, DocumentDB, Valkey, Kafka
### External
- fastapi
- uvicorn
- aiokafka
- numpy (for ML computations)

<!-- MANUAL: -->
