"""Review Service - FastAPI Application with stub responses."""

from datetime import datetime
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="review")
app = FastAPI(title="Review Service", version="1.0.0")

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

# Mock reviews - consistent with shared IDs, Korean content
MOCK_REVIEWS = [
    # PRD-001 삼성 갤럭시 S25 울트라 reviews
    {
        "review_id": "rev-001",
        "product_id": "PRD-001",
        "user_id": "USR-002",
        "user_name": "이서연",
        "rating": 5,
        "title": "최고의 스마트폰입니다!",
        "content": "카메라 성능이 정말 대단해요. AI 기능도 유용하고 배터리도 오래가요. S펜 기능도 자주 사용하게 됩니다.",
        "verified_purchase": True,
        "helpful_votes": 142,
        "images": ["https://placehold.co/200x200/EEE/333?text=Review1"],
        "created_at": "2026-03-10T15:30:00Z",
    },
    {
        "review_id": "rev-002",
        "product_id": "PRD-001",
        "user_id": "USR-003",
        "user_name": "박지훈",
        "rating": 4,
        "title": "만족스럽지만 가격이...",
        "content": "성능은 정말 좋은데 가격이 좀 부담되네요. 그래도 2년은 쓸 것 같아서 투자했습니다.",
        "verified_purchase": True,
        "helpful_votes": 89,
        "images": [],
        "created_at": "2026-03-12T09:45:00Z",
    },
    {
        "review_id": "rev-003",
        "product_id": "PRD-001",
        "user_id": "USR-001",
        "user_name": "김민수",
        "rating": 5,
        "title": "갤럭시 최고봉",
        "content": "S24에서 업그레이드 했는데 확실히 차이가 나요. 특히 야간 촬영이 훨씬 좋아졌어요.",
        "verified_purchase": True,
        "helpful_votes": 67,
        "images": [],
        "created_at": "2026-03-14T20:15:00Z",
    },
    # PRD-002 나이키 에어맥스 97 reviews
    {
        "review_id": "rev-004",
        "product_id": "PRD-002",
        "user_id": "USR-001",
        "user_name": "김민수",
        "rating": 5,
        "title": "클래식한 디자인 최고",
        "content": "역시 에어맥스97은 클래식하면서도 세련됐어요. 편하고 예쁘고 만족합니다!",
        "verified_purchase": True,
        "helpful_votes": 45,
        "images": [],
        "created_at": "2026-03-08T11:20:00Z",
    },
    {
        "review_id": "rev-005",
        "product_id": "PRD-002",
        "user_id": "USR-003",
        "user_name": "박지훈",
        "rating": 4,
        "title": "사이즈 약간 작아요",
        "content": "평소 신던 사이즈로 주문했는데 살짝 작은 느낌. 반 사이즈 업 추천드려요.",
        "verified_purchase": True,
        "helpful_votes": 112,
        "images": [],
        "created_at": "2026-03-11T16:30:00Z",
    },
    # PRD-003 다이슨 에어랩 reviews
    {
        "review_id": "rev-006",
        "product_id": "PRD-003",
        "user_id": "USR-002",
        "user_name": "이서연",
        "rating": 5,
        "title": "머리 손상 없이 스타일링!",
        "content": "고데기 쓸 때 머리 많이 상했는데 에어랩은 열 손상이 적어서 좋아요. 컬도 자연스럽게 나와요.",
        "verified_purchase": True,
        "helpful_votes": 234,
        "images": ["https://placehold.co/200x200/EEE/333?text=Airwrap1"],
        "created_at": "2026-03-05T14:00:00Z",
    },
    {
        "review_id": "rev-007",
        "product_id": "PRD-003",
        "user_id": "USR-001",
        "user_name": "김민수",
        "rating": 5,
        "title": "여자친구 선물로 구매",
        "content": "여자친구한테 선물했더니 너무 좋아해요. 비싸지만 그만한 가치가 있는 것 같습니다.",
        "verified_purchase": True,
        "helpful_votes": 78,
        "images": [],
        "created_at": "2026-03-15T19:45:00Z",
    },
    # PRD-007 LG 올레드 TV reviews
    {
        "review_id": "rev-008",
        "product_id": "PRD-007",
        "user_id": "USR-003",
        "user_name": "박지훈",
        "rating": 5,
        "title": "OLED 화질은 진리",
        "content": "이사하면서 TV 바꿨는데 OLED 화질 정말 다르네요. 영화 볼 때 몰입감이 엄청납니다.",
        "verified_purchase": True,
        "helpful_votes": 156,
        "images": [],
        "created_at": "2026-03-02T20:30:00Z",
    },
    {
        "review_id": "rev-009",
        "product_id": "PRD-007",
        "user_id": "USR-002",
        "user_name": "이서연",
        "rating": 4,
        "title": "설치 서비스 좋았어요",
        "content": "화질 완벽하고 설치 기사님도 친절하셨어요. 다만 리모컨이 좀 불편해요.",
        "verified_purchase": True,
        "helpful_votes": 43,
        "images": [],
        "created_at": "2026-03-09T10:15:00Z",
    },
    # PRD-010 소니 WH-1000XM5 reviews
    {
        "review_id": "rev-010",
        "product_id": "PRD-010",
        "user_id": "USR-001",
        "user_name": "김민수",
        "rating": 5,
        "title": "노캔 끝판왕",
        "content": "지하철에서 노캔 켜면 세상이 조용해져요. 음질도 좋고 착용감도 편해요. 강추!",
        "verified_purchase": True,
        "helpful_votes": 198,
        "images": [],
        "created_at": "2026-03-07T08:45:00Z",
    },
    {
        "review_id": "rev-011",
        "product_id": "PRD-010",
        "user_id": "USR-002",
        "user_name": "이서연",
        "rating": 5,
        "title": "재택근무 필수템",
        "content": "집에서 일할 때 집중하기 좋아요. 멀티포인트 연결로 폰이랑 노트북 동시 연결도 편해요.",
        "verified_purchase": True,
        "helpful_votes": 87,
        "images": [],
        "created_at": "2026-03-13T13:20:00Z",
    },
]


@app.get("/")
async def root():
    return {"service": "review", "status": "running"}


@app.get("/api/v1/reviews/product/{product_id}")
async def get_product_reviews(product_id: str, limit: int = 10, offset: int = 0):
    """Get reviews for a product."""
    reviews = [r for r in MOCK_REVIEWS if r["product_id"] == product_id]
    avg_rating = sum(r["rating"] for r in reviews) / len(reviews) if reviews else 0

    rating_dist = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0}
    for r in reviews:
        rating_dist[r["rating"]] += 1

    return {
        "product_id": product_id,
        "reviews": reviews[offset : offset + limit],
        "total": len(reviews),
        "average_rating": round(avg_rating, 1),
        "rating_distribution": rating_dist,
        "limit": limit,
        "offset": offset,
    }


@app.post("/api/v1/reviews")
async def create_review(review: dict):
    """Create a new review (stub - returns mock response)."""
    return {
        "review_id": f"rev-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}",
        "product_id": review.get("product_id", "unknown"),
        "user_id": review.get("user_id", "unknown"),
        "rating": review.get("rating", 5),
        "title": review.get("title", ""),
        "content": review.get("content", ""),
        "verified_purchase": False,
        "helpful_votes": 0,
        "created_at": datetime.utcnow().isoformat(),
        "created": True,
        "message": "리뷰가 등록되었습니다",
    }


@app.get("/api/v1/reviews/{review_id}")
async def get_review(review_id: str):
    """Get a single review by ID."""
    for review in MOCK_REVIEWS:
        if review["review_id"] == review_id:
            return review
    raise HTTPException(status_code=404, detail="리뷰를 찾을 수 없습니다")


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
