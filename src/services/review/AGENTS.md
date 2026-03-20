<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# review/

## Purpose
Python FastAPI product review service managing customer reviews, ratings, and review moderation. Calculates aggregate ratings and supports helpful votes.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/review.py` | Pydantic review models |
| `app/repositories/review_repo.py` | DocumentDB repository |
| `app/services/review_service.py` | Review business logic |
| `app/routers/reviews.py` | Review REST endpoints |
| `app/routers/health.py` | Health check endpoint |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/repositories/` | DocumentDB access |
| `app/services/` | Business logic |
| `app/routers/` | FastAPI route handlers |

## For AI Agents

### Working In This Directory
- Reviews linked to products and verified purchases
- Aggregate ratings cached and updated on new reviews
- Moderation status: PENDING, APPROVED, REJECTED

### Common Patterns
```python
# Aggregate rating calculation
async def update_product_rating(product_id: str):
    pipeline = [
        {"$match": {"product_id": product_id, "status": "APPROVED"}},
        {"$group": {"_id": None, "avg": {"$avg": "$rating"}, "count": {"$sum": 1}}}
    ]
    result = await reviews.aggregate(pipeline).to_list(1)
    await products.update_one(
        {"_id": product_id},
        {"$set": {"avg_rating": result[0]["avg"], "review_count": result[0]["count"]}}
    )
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, DocumentDB
### External
- fastapi
- uvicorn
- motor
- pydantic

<!-- MANUAL: -->
