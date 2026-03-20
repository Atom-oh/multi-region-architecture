"""Recommendation Service - FastAPI Application with stub responses."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="recommendation")
app = FastAPI(title="Recommendation Service", version="1.0.0")

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

# Mock recommendations - consistent with shared IDs
MOCK_USER_RECOMMENDATIONS = {
    "USR-001": [
        {
            "product_id": "PRD-004",
            "name": "애플 맥북 프로 M4",
            "price": 2990000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=MacBook+M4",
            "score": 0.95,
            "reason": "최근 본 전자제품과 비슷한 상품",
        },
        {
            "product_id": "PRD-007",
            "name": "LG 올레드 TV 65\"",
            "price": 3290000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=LG+OLED+65",
            "score": 0.92,
            "reason": "같은 카테고리 인기 상품",
        },
        {
            "product_id": "PRD-003",
            "name": "다이슨 에어랩",
            "price": 699000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap",
            "score": 0.88,
            "reason": "위시리스트 기반 추천",
        },
        {
            "product_id": "PRD-006",
            "name": "아디다스 울트라부스트",
            "price": 219000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Ultraboost",
            "score": 0.85,
            "reason": "비슷한 고객이 구매한 상품",
        },
        {
            "product_id": "PRD-009",
            "name": "스타벅스 텀블러 세트",
            "price": 45000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Starbucks",
            "score": 0.82,
            "reason": "지금 인기 있는 상품",
        },
    ],
    "USR-002": [
        {
            "product_id": "PRD-003",
            "name": "다이슨 에어랩",
            "price": 699000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap",
            "score": 0.96,
            "reason": "뷰티 카테고리 베스트셀러",
        },
        {
            "product_id": "PRD-005",
            "name": "르크루제 냄비 세트",
            "price": 459000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Le+Creuset",
            "score": 0.91,
            "reason": "프리미엄 라이프스타일 추천",
        },
        {
            "product_id": "PRD-010",
            "name": "소니 WH-1000XM5",
            "price": 429000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Sony+XM5",
            "score": 0.87,
            "reason": "최근 검색한 상품과 유사",
        },
        {
            "product_id": "PRD-008",
            "name": "무지 캔버스 토트백",
            "price": 29000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=MUJI+Tote",
            "score": 0.83,
            "reason": "함께 보면 좋은 상품",
        },
    ],
    "USR-003": [
        {
            "product_id": "PRD-002",
            "name": "나이키 에어맥스 97",
            "price": 189000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=AirMax+97",
            "score": 0.94,
            "reason": "관심 카테고리 베스트",
        },
        {
            "product_id": "PRD-006",
            "name": "아디다스 울트라부스트",
            "price": 219000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Ultraboost",
            "score": 0.92,
            "reason": "위시리스트 상품과 유사",
        },
        {
            "product_id": "PRD-008",
            "name": "무지 캔버스 토트백",
            "price": 29000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=MUJI+Tote",
            "score": 0.85,
            "reason": "함께 구매하면 좋은 상품",
        },
        {
            "product_id": "PRD-009",
            "name": "스타벅스 텀블러 세트",
            "price": 45000,
            "image_url": "https://placehold.co/400x400/EEE/333?text=Starbucks",
            "score": 0.80,
            "reason": "지역 인기 상품",
        },
    ],
}

MOCK_TRENDING = [
    {
        "product_id": "PRD-001",
        "name": "삼성 갤럭시 S25 울트라",
        "price": 1890000,
        "image_url": "https://placehold.co/400x400/EEE/333?text=Galaxy+S25",
        "trend_score": 0.98,
        "sales_increase": "45%",
        "rank": 1,
    },
    {
        "product_id": "PRD-003",
        "name": "다이슨 에어랩",
        "price": 699000,
        "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap",
        "trend_score": 0.95,
        "sales_increase": "38%",
        "rank": 2,
    },
    {
        "product_id": "PRD-007",
        "name": "LG 올레드 TV 65\"",
        "price": 3290000,
        "image_url": "https://placehold.co/400x400/EEE/333?text=LG+OLED+65",
        "trend_score": 0.92,
        "sales_increase": "32%",
        "rank": 3,
    },
    {
        "product_id": "PRD-010",
        "name": "소니 WH-1000XM5",
        "price": 429000,
        "image_url": "https://placehold.co/400x400/EEE/333?text=Sony+XM5",
        "trend_score": 0.89,
        "sales_increase": "28%",
        "rank": 4,
    },
    {
        "product_id": "PRD-004",
        "name": "애플 맥북 프로 M4",
        "price": 2990000,
        "image_url": "https://placehold.co/400x400/EEE/333?text=MacBook+M4",
        "trend_score": 0.87,
        "sales_increase": "25%",
        "rank": 5,
    },
]

MOCK_SIMILAR = {
    "PRD-001": [
        {"product_id": "PRD-004", "name": "애플 맥북 프로 M4", "price": 2990000, "image_url": "https://placehold.co/400x400/EEE/333?text=MacBook+M4", "similarity": 0.75},
        {"product_id": "PRD-007", "name": "LG 올레드 TV 65\"", "price": 3290000, "image_url": "https://placehold.co/400x400/EEE/333?text=LG+OLED+65", "similarity": 0.68},
        {"product_id": "PRD-010", "name": "소니 WH-1000XM5", "price": 429000, "image_url": "https://placehold.co/400x400/EEE/333?text=Sony+XM5", "similarity": 0.65},
        {"product_id": "PRD-003", "name": "다이슨 에어랩", "price": 699000, "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap", "similarity": 0.55},
    ],
    "PRD-002": [
        {"product_id": "PRD-006", "name": "아디다스 울트라부스트", "price": 219000, "image_url": "https://placehold.co/400x400/EEE/333?text=Ultraboost", "similarity": 0.95},
        {"product_id": "PRD-008", "name": "무지 캔버스 토트백", "price": 29000, "image_url": "https://placehold.co/400x400/EEE/333?text=MUJI+Tote", "similarity": 0.45},
        {"product_id": "PRD-009", "name": "스타벅스 텀블러 세트", "price": 45000, "image_url": "https://placehold.co/400x400/EEE/333?text=Starbucks", "similarity": 0.35},
        {"product_id": "PRD-005", "name": "르크루제 냄비 세트", "price": 459000, "image_url": "https://placehold.co/400x400/EEE/333?text=Le+Creuset", "similarity": 0.30},
    ],
    "PRD-003": [
        {"product_id": "PRD-005", "name": "르크루제 냄비 세트", "price": 459000, "image_url": "https://placehold.co/400x400/EEE/333?text=Le+Creuset", "similarity": 0.72},
        {"product_id": "PRD-009", "name": "스타벅스 텀블러 세트", "price": 45000, "image_url": "https://placehold.co/400x400/EEE/333?text=Starbucks", "similarity": 0.65},
        {"product_id": "PRD-008", "name": "무지 캔버스 토트백", "price": 29000, "image_url": "https://placehold.co/400x400/EEE/333?text=MUJI+Tote", "similarity": 0.58},
        {"product_id": "PRD-010", "name": "소니 WH-1000XM5", "price": 429000, "image_url": "https://placehold.co/400x400/EEE/333?text=Sony+XM5", "similarity": 0.52},
    ],
}


@app.get("/")
async def root():
    return {"service": "recommendation", "status": "running"}


@app.get("/api/v1/recommendations/{user_id}")
async def get_user_recommendations(user_id: str, limit: int = 10):
    """Get personalized recommendations for a user."""
    recommendations = MOCK_USER_RECOMMENDATIONS.get(user_id, MOCK_TRENDING[:5])
    return {
        "user_id": user_id,
        "recommendations": recommendations[:limit],
        "total": len(recommendations),
        "algorithm": "collaborative_filtering_v2",
    }


@app.get("/api/v1/recommendations/trending")
async def get_trending(limit: int = 10, category: str = None):
    """Get trending products."""
    products = MOCK_TRENDING
    return {
        "trending": products[:limit],
        "total": len(products),
        "category": category,
        "period": "last_7_days",
    }


@app.get("/api/v1/recommendations/similar/{product_id}")
async def get_similar_products(product_id: str, limit: int = 5):
    """Get similar products."""
    similar = MOCK_SIMILAR.get(product_id, [])
    return {
        "product_id": product_id,
        "similar_products": similar[:limit],
        "total": len(similar),
        "algorithm": "content_based_filtering",
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
