<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# product-catalog/

## Purpose
Python FastAPI product catalog service managing product CRUD operations with DocumentDB (MongoDB). Publishes catalog events for search indexing and recommendation updates.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/product.py` | Pydantic product models |
| `app/repositories/product_repo.py` | DocumentDB repository |
| `app/services/product_service.py` | Product business logic |
| `app/routers/products.py` | Product REST endpoints |
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
- Uses async Motor driver for DocumentDB
- Products stored in `products` collection
- Publishes catalog.product.created/updated/deleted events

### Common Patterns
```python
# Async repository pattern
class ProductRepository:
    async def find_by_id(self, product_id: str) -> Optional[Product]:
        doc = await self.collection.find_one({"_id": ObjectId(product_id)})
        return Product(**doc) if doc else None
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, DocumentDB, Kafka
### External
- fastapi
- uvicorn
- motor (async MongoDB)
- pydantic

<!-- MANUAL: -->
