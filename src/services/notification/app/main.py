"""Notification Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="notification")
app = FastAPI(title="Notification Service", version="1.0.0")

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

# Mock notifications - consistent with shared IDs, Korean content
MOCK_NOTIFICATIONS = {
    "USR-001": [
        {
            "id": "notif-001",
            "user_id": "USR-001",
            "type": "order_delivered",
            "title": "배송이 완료되었습니다",
            "message": "주문하신 삼성 갤럭시 S25 울트라, 소니 WH-1000XM5 상품이 배송 완료되었습니다. 상품은 마음에 드셨나요?",
            "order_id": "ORD-001",
            "read": False,
            "action_url": "/orders/ORD-001",
            "created_at": "2026-03-18T14:35:00Z",
        },
        {
            "id": "notif-002",
            "user_id": "USR-001",
            "type": "price_drop",
            "title": "위시리스트 상품 가격 인하!",
            "message": "관심 등록하신 LG 올레드 TV 65\"가 3,590,000원에서 3,290,000원으로 300,000원 할인되었습니다!",
            "product_id": "PRD-007",
            "read": True,
            "action_url": "/products/PRD-007",
            "created_at": "2026-03-17T10:00:00Z",
        },
        {
            "id": "notif-003",
            "user_id": "USR-001",
            "type": "promotion",
            "title": "GOLD 회원 전용 혜택",
            "message": "김민수님을 위한 특별 쿠폰! 전자제품 카테고리 15% 할인 쿠폰이 발급되었습니다. (~3/25)",
            "read": False,
            "action_url": "/coupons",
            "created_at": "2026-03-16T09:00:00Z",
        },
        {
            "id": "notif-004",
            "user_id": "USR-001",
            "type": "review_reply",
            "title": "내 리뷰에 댓글이 달렸습니다",
            "message": "삼성전자 Official에서 회원님의 리뷰에 감사 인사를 남겼습니다.",
            "review_id": "rev-003",
            "read": True,
            "action_url": "/reviews/rev-003",
            "created_at": "2026-03-15T16:20:00Z",
        },
        {
            "id": "notif-005",
            "user_id": "USR-001",
            "type": "points_earned",
            "title": "포인트가 적립되었습니다",
            "message": "주문 ORD-001 구매 확정으로 23,190 포인트가 적립되었습니다. 누적 포인트: 125,000P",
            "read": False,
            "action_url": "/mypage/points",
            "created_at": "2026-03-18T15:00:00Z",
        },
    ],
    "USR-002": [
        {
            "id": "notif-006",
            "user_id": "USR-002",
            "type": "order_shipped",
            "title": "주문하신 상품이 발송되었습니다",
            "message": "다이슨 에어랩 상품이 발송되었습니다. 운송장번호: HANJIN9876543210",
            "order_id": "ORD-002",
            "read": False,
            "action_url": "/orders/ORD-002",
            "created_at": "2026-03-19T16:10:00Z",
        },
        {
            "id": "notif-007",
            "user_id": "USR-002",
            "type": "promotion",
            "title": "PLATINUM 회원 특별 혜택",
            "message": "이서연님, PLATINUM 등급 유지를 축하드립니다! 다음 달 무료배송 쿠폰 5장이 지급되었습니다.",
            "read": True,
            "action_url": "/coupons",
            "created_at": "2026-03-01T00:00:00Z",
        },
        {
            "id": "notif-008",
            "user_id": "USR-002",
            "type": "stock_alert",
            "title": "관심 상품 재입고 알림",
            "message": "품절되었던 애플 맥북 프로 M4 상품이 재입고되었습니다. 지금 바로 확인하세요!",
            "product_id": "PRD-004",
            "read": False,
            "action_url": "/products/PRD-004",
            "created_at": "2026-03-20T11:00:00Z",
        },
    ],
    "USR-003": [
        {
            "id": "notif-009",
            "user_id": "USR-003",
            "type": "order_processing",
            "title": "주문이 접수되었습니다",
            "message": "나이키 에어맥스 97, 무지 캔버스 토트백 주문이 접수되었습니다. 빠르게 준비해 드릴게요!",
            "order_id": "ORD-003",
            "read": True,
            "action_url": "/orders/ORD-003",
            "created_at": "2026-03-20T10:05:00Z",
        },
        {
            "id": "notif-010",
            "user_id": "USR-003",
            "type": "price_drop",
            "title": "위시리스트 상품 세일 중!",
            "message": "찜한 아디다스 울트라부스트가 239,000원에서 219,000원으로 할인 중입니다!",
            "product_id": "PRD-006",
            "read": False,
            "action_url": "/products/PRD-006",
            "created_at": "2026-03-19T08:00:00Z",
        },
        {
            "id": "notif-011",
            "user_id": "USR-003",
            "type": "promotion",
            "title": "부산 지역 특별 이벤트",
            "message": "부산 거주 고객님 한정! 신발 카테고리 20% 추가 할인 쿠폰을 드립니다. (~3/31)",
            "read": False,
            "action_url": "/events/busan-special",
            "created_at": "2026-03-15T10:00:00Z",
        },
    ],
}


@app.get("/")
async def root():
    return {"service": "notification", "status": "running"}


@app.post("/api/v1/notifications")
async def create_notification(notification: dict):
    """Create a new notification (stub - returns acknowledgment)."""
    return {
        "id": f"notif-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "user_id": notification.get("user_id", "unknown"),
        "type": notification.get("type", "general"),
        "title": notification.get("title", "알림"),
        "message": notification.get("message", ""),
        "read": False,
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
        "message_status": "알림이 발송되었습니다",
    }


@app.get("/api/v1/notifications/{user_id}")
async def get_notifications(user_id: str, unread_only: bool = False, limit: int = 20):
    """Get notifications for a user."""
    notifications = MOCK_NOTIFICATIONS.get(user_id, [])
    if unread_only:
        notifications = [n for n in notifications if not n["read"]]
    unread_count = len([n for n in MOCK_NOTIFICATIONS.get(user_id, []) if not n["read"]])
    return {
        "user_id": user_id,
        "notifications": notifications[:limit],
        "total": len(notifications),
        "unread_count": unread_count,
    }


@app.put("/api/v1/notifications/{notification_id}/read")
async def mark_read(notification_id: str):
    """Mark notification as read (stub - returns acknowledgment)."""
    return {
        "id": notification_id,
        "read": True,
        "read_at": datetime.utcnow().isoformat(),
        "updated": True,
        "message": "알림을 읽음 처리했습니다",
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
