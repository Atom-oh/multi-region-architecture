<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# shared/python/

## Purpose
Python mall_common package providing shared utilities for tracing, database connections, caching, messaging, and health checks for the 8 Python microservices.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Package dependencies |
| `mall_common/__init__.py` | Package exports |
| `mall_common/tracing.py` | OpenTelemetry setup |
| `mall_common/documentdb.py` | DocumentDB/MongoDB client |
| `mall_common/valkey.py` | Valkey/Redis async client |
| `mall_common/kafka.py` | Kafka producer/consumer |
| `mall_common/health.py` | Health check utilities |
| `mall_common/region.py` | Region detection utilities |
| `mall_common/config.py` | Environment configuration |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `mall_common/` | Main package with all modules |

## For AI Agents

### Working In This Directory
- Use async/await patterns throughout
- Follow PEP 8 style guidelines
- Type hints are required for all functions

### Common Patterns
```python
# Tracing setup
from mall_common.tracing import setup_tracing
tracer = setup_tracing("service-name")

# DocumentDB connection
from mall_common.documentdb import get_database
db = await get_database()

# Region detection
from mall_common.region import get_current_region, is_primary_region
```

## Dependencies
### Internal
- Used by: product-catalog, shipping, user-profile, recommendation, wishlist, analytics, notification, review
### External
- opentelemetry-api, opentelemetry-sdk
- motor (async MongoDB driver)
- aiokafka
- redis (async)
- pydantic

<!-- MANUAL: -->
