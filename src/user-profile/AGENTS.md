<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# user-profile/

## Purpose
Python FastAPI user profile service managing user preferences, addresses, and personalization settings. Stores flexible profile data in DocumentDB.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/profile.py` | Pydantic profile models |
| `app/repositories/profile_repo.py` | DocumentDB repository |
| `app/services/profile_service.py` | Profile business logic |
| `app/routers/profiles.py` | Profile REST endpoints |
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
- Profiles linked to user-account by userId
- Supports multiple addresses per user
- Preferences stored as flexible JSON document

### Common Patterns
```python
# Profile with nested addresses
class Profile(BaseModel):
    user_id: str
    addresses: List[Address] = []
    preferences: Dict[str, Any] = {}
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
