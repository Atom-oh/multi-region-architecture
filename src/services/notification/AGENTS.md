<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-03-15 -->

# notification/

## Purpose
Python FastAPI notification service handling multi-channel notifications (email, SMS, push) triggered by platform events. Supports templating and delivery tracking.

## Key Files
| File | Description |
|------|-------------|
| `requirements.txt` | Python dependencies |
| `Dockerfile` | Container build definition |
| `app/main.py` | FastAPI application entry |
| `app/config.py` | Configuration settings |
| `app/models/notification.py` | Pydantic notification models |
| `app/services/notification_service.py` | Notification dispatch logic |
| `app/routers/notifications.py` | Notification REST endpoints |
| `app/routers/health.py` | Health check endpoint |
| `app/consumers/event_consumers.py` | Kafka event consumers |

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `app/` | Main application package |
| `app/models/` | Pydantic data models |
| `app/services/` | Notification services |
| `app/routers/` | FastAPI route handlers |
| `app/consumers/` | Kafka event consumers |

## For AI Agents

### Working In This Directory
- Channels: EMAIL, SMS, PUSH
- Uses AWS SES for email, SNS for SMS/push
- Event-to-notification mapping in config

### Common Patterns
```python
# Multi-channel dispatch
async def send_notification(user_id: str, template: str, channels: List[str]):
    user = await get_user_preferences(user_id)
    for channel in channels:
        if channel in user.enabled_channels:
            await dispatch(channel, user, template)
```

## Dependencies
### Internal
- `shared/python/mall_common` for tracing, Kafka
### External
- fastapi
- uvicorn
- aiokafka
- aiobotocore (SES, SNS)

<!-- MANUAL: -->
