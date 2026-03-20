"""User Profile Service - FastAPI Application with stub responses."""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="user-profile")
app = FastAPI(title="User Profile Service", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock user profiles - consistent with shared user IDs
MOCK_PROFILES = {
    "USR-001": {
        "user_id": "USR-001",
        "email": "minsu@example.com",
        "name": "김민수",
        "phone": "010-1234-5678",
        "birth_date": "1990-05-15",
        "gender": "male",
        "address": {
            "street": "테헤란로 123",
            "detail": "멀티리전타워 15층",
            "city": "서울특별시",
            "district": "강남구",
            "zip": "06234",
            "country": "대한민국",
        },
        "created_at": "2025-01-15T10:30:00Z",
        "membership": {
            "tier": "GOLD",
            "points": 125000,
            "total_spent": 8523000,
        },
        "preferences": {
            "language": "ko",
            "currency": "KRW",
            "notifications": {"email": True, "sms": True, "push": True, "kakao": True},
            "marketing": True,
        },
    },
    "USR-002": {
        "user_id": "USR-002",
        "email": "seoyeon@example.com",
        "name": "이서연",
        "phone": "010-9876-5432",
        "birth_date": "1995-11-23",
        "gender": "female",
        "address": {
            "street": "강남대로 456",
            "detail": "힐스테이트 1203호",
            "city": "서울특별시",
            "district": "서초구",
            "zip": "06612",
            "country": "대한민국",
        },
        "created_at": "2025-02-20T14:45:00Z",
        "membership": {
            "tier": "PLATINUM",
            "points": 342000,
            "total_spent": 15892000,
        },
        "preferences": {
            "language": "ko",
            "currency": "KRW",
            "notifications": {"email": True, "sms": False, "push": True, "kakao": True},
            "marketing": False,
        },
    },
    "USR-003": {
        "user_id": "USR-003",
        "email": "jihoon@example.com",
        "name": "박지훈",
        "phone": "010-5555-7777",
        "birth_date": "1988-03-08",
        "gender": "male",
        "address": {
            "street": "해운대로 789",
            "detail": "마린시티 2501호",
            "city": "부산광역시",
            "district": "해운대구",
            "zip": "48099",
            "country": "대한민국",
        },
        "created_at": "2025-03-10T09:15:00Z",
        "membership": {
            "tier": "SILVER",
            "points": 45000,
            "total_spent": 2150000,
        },
        "preferences": {
            "language": "ko",
            "currency": "KRW",
            "notifications": {"email": True, "sms": True, "push": False, "kakao": False},
            "marketing": True,
        },
    },
}


@app.get("/")
async def root():
    return {"service": "user-profile", "status": "running"}


@app.get("/api/v1/profiles/{user_id}")
async def get_profile(user_id: str):
    """Get user profile by ID."""
    if user_id in MOCK_PROFILES:
        return MOCK_PROFILES[user_id]
    raise HTTPException(status_code=404, detail="프로필을 찾을 수 없습니다")


@app.put("/api/v1/profiles/{user_id}")
async def update_profile(user_id: str, profile: dict):
    """Update user profile (stub - returns merged data)."""
    base = MOCK_PROFILES.get(user_id, {"user_id": user_id})
    return {
        **base,
        **profile,
        "user_id": user_id,
        "updated": True,
        "message": "프로필이 업데이트되었습니다",
    }


@app.get("/api/v1/profiles/{user_id}/preferences")
async def get_preferences(user_id: str):
    """Get user preferences."""
    if user_id in MOCK_PROFILES:
        return {
            "user_id": user_id,
            "preferences": MOCK_PROFILES[user_id]["preferences"],
        }
    raise HTTPException(status_code=404, detail="프로필을 찾을 수 없습니다")


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
