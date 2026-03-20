<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# wishlist/

## Purpose
Python FastAPI wishlist service managing user wishlists with Valkey for fast access. Supports add, remove, and price drop notifications for wishlist items.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/wishlist.py` | Pydantic wishlist models |
| `app/repositories/wishlist_repo.py` | Valkey repository |
| `app/services/wishlist_service.py` | Wishlist business logic |
| `app/routers/wishlists.py` | Wishlist REST endpoints |
| `app/routers/health.py` | Health check endpoint |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/repositories/` | Valkey storage |
| `app/services/` | Business logic |
| `app/routers/` | FastAPI route handlers |

## For AI Agents

### Working In This Directory
- Wishlists stored in Valkey sets: `wishlist:{userId}`
- Item details fetched from product-catalog on read
- Supports price alert subscriptions

### Common Patterns
```python
# Valkey set operations
async def add_to_wishlist(user_id: str, product_id: str):
    await valkey.sadd(f"wishlist:{user_id}", product_id)

async def get_wishlist(user_id: str) -> List[str]:
    return await valkey.smembers(f"wishlist:{user_id}")
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, Valkey
### External
- fastapi
- uvicorn
- redis (async)
- pydantic

<!-- MANUAL: -->
