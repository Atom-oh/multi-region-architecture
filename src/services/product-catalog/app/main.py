"""Product Catalog Service - FastAPI Application."""

import logging
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from mall_common.config import ServiceConfig
from mall_common.documentdb import connect, disconnect, get_db
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

logger = logging.getLogger(__name__)
config = ServiceConfig(service_name="product-catalog")
app = FastAPI(title="Product Catalog Service", version="1.0.0")
_db_connected = False

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

# Mock data - consistent with shared IDs
MOCK_PRODUCTS = [
    {
        "id": "PRD-001",
        "name": "삼성 갤럭시 S25 울트라",
        "price": 1890000,
        "original_price": 1990000,
        "category": "electronics",
        "description": "최신 AI 기능을 탑재한 삼성의 플래그십 스마트폰. 2억 화소 카메라와 S펜 지원.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Galaxy+S25",
        "seller_id": "SEL-001",
        "seller_name": "삼성전자 Official",
        "rating": 4.8,
        "review_count": 1523,
        "stock": 150,
        "tags": ["베스트", "무료배송", "삼성케어+"],
    },
    {
        "id": "PRD-002",
        "name": "나이키 에어맥스 97",
        "price": 189000,
        "original_price": 219000,
        "category": "shoes",
        "description": "클래식한 웨이브 디자인의 아이코닉 러닝화. 풀 렝스 에어 유닛 탑재.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=AirMax+97",
        "seller_id": "SEL-002",
        "seller_name": "Nike Korea",
        "rating": 4.6,
        "review_count": 892,
        "stock": 89,
        "tags": ["세일", "무료배송"],
    },
    {
        "id": "PRD-003",
        "name": "다이슨 에어랩",
        "price": 699000,
        "original_price": 699000,
        "category": "beauty",
        "description": "코안다 기술을 적용한 멀티 스타일러. 드라이, 컬, 스트레이트 올인원.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Dyson+Airwrap",
        "seller_id": "SEL-003",
        "seller_name": "Dyson Korea",
        "rating": 4.9,
        "review_count": 2341,
        "stock": 45,
        "tags": ["베스트", "프리미엄"],
    },
    {
        "id": "PRD-004",
        "name": "애플 맥북 프로 M4",
        "price": 2990000,
        "original_price": 2990000,
        "category": "electronics",
        "description": "M4 칩 탑재 프로페셔널 노트북. 18시간 배터리, Liquid Retina XDR 디스플레이.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=MacBook+M4",
        "seller_id": "SEL-004",
        "seller_name": "Apple Korea",
        "rating": 4.9,
        "review_count": 756,
        "stock": 72,
        "tags": ["신상품", "프리미엄"],
    },
    {
        "id": "PRD-005",
        "name": "르크루제 냄비 세트",
        "price": 459000,
        "original_price": 550000,
        "category": "kitchen",
        "description": "프랑스 장인이 만든 주철 냄비 3종 세트. 26cm, 22cm, 18cm 구성.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Le+Creuset",
        "seller_id": "SEL-005",
        "seller_name": "Le Creuset Korea",
        "rating": 4.7,
        "review_count": 445,
        "stock": 120,
        "tags": ["세일", "웨딩선물"],
    },
    {
        "id": "PRD-006",
        "name": "아디다스 울트라부스트",
        "price": 219000,
        "original_price": 239000,
        "category": "shoes",
        "description": "BOOST 쿠셔닝 기술 적용 프리미엄 러닝화. 통기성 프라임닛+ 어퍼.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Ultraboost",
        "seller_id": "SEL-006",
        "seller_name": "Adidas Korea",
        "rating": 4.5,
        "review_count": 1102,
        "stock": 200,
        "tags": ["무료배송"],
    },
    {
        "id": "PRD-007",
        "name": "LG 올레드 TV 65\"",
        "price": 3290000,
        "original_price": 3590000,
        "category": "electronics",
        "description": "65인치 4K OLED 스마트 TV. a9 AI 프로세서, 돌비 비전 IQ.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=LG+OLED+65",
        "seller_id": "SEL-007",
        "seller_name": "LG전자 Official",
        "rating": 4.8,
        "review_count": 634,
        "stock": 35,
        "tags": ["베스트", "무료설치"],
    },
    {
        "id": "PRD-008",
        "name": "무지 캔버스 토트백",
        "price": 29000,
        "original_price": 35000,
        "category": "fashion",
        "description": "심플한 디자인의 캔버스 토트백. 내부 포켓, A4 수납 가능.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=MUJI+Tote",
        "seller_id": "SEL-008",
        "seller_name": "MUJI Korea",
        "rating": 4.3,
        "review_count": 2156,
        "stock": 500,
        "tags": ["세일", "친환경"],
    },
    {
        "id": "PRD-009",
        "name": "스타벅스 텀블러 세트",
        "price": 45000,
        "original_price": 52000,
        "category": "kitchen",
        "description": "스테인리스 스틸 텀블러 2종 세트. 473ml, 355ml 구성. 보온보냉 6시간.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Starbucks",
        "seller_id": "SEL-009",
        "seller_name": "Starbucks Korea",
        "rating": 4.4,
        "review_count": 1876,
        "stock": 300,
        "tags": ["세일", "한정판"],
    },
    {
        "id": "PRD-010",
        "name": "소니 WH-1000XM5",
        "price": 429000,
        "original_price": 459000,
        "category": "electronics",
        "description": "프리미엄 노이즈캔슬링 무선 헤드폰. 30시간 재생, 멀티포인트 연결.",
        "image_url": "https://placehold.co/400x400/EEE/333?text=Sony+XM5",
        "seller_id": "SEL-010",
        "seller_name": "Sony Korea",
        "rating": 4.8,
        "review_count": 982,
        "stock": 85,
        "tags": ["베스트", "무료배송"],
    },
]

MOCK_CATEGORIES = [
    {"name": "electronics", "display_name": "전자제품", "count": 4},
    {"name": "shoes", "display_name": "신발", "count": 2},
    {"name": "beauty", "display_name": "뷰티", "count": 1},
    {"name": "kitchen", "display_name": "주방용품", "count": 2},
    {"name": "fashion", "display_name": "패션", "count": 1},
]


@app.get("/")
async def root():
    return {"service": "product-catalog", "status": "running"}


@app.get("/api/v1/products")
async def list_products(category: str = None, limit: int = 10, offset: int = 0):
    """List all products with optional category filter."""
    if _db_connected:
        try:
            db = get_db()
            query = {}
            if category:
                query["category.slug"] = category
            cursor = db["products"].find(query).skip(offset).limit(limit)
            products = []
            async for doc in cursor:
                doc["_id"] = str(doc["_id"])
                products.append(doc)
            total = await db["products"].count_documents(query)
            return {
                "products": products,
                "total": total,
                "limit": limit,
                "offset": offset,
            }
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, using fallback mock data")
    # Fallback to mock data
    products = MOCK_PRODUCTS
    if category:
        products = [p for p in products if p["category"] == category]
    return {
        "products": products[offset : offset + limit],
        "total": len(products),
        "limit": limit,
        "offset": offset,
    }


@app.get("/api/v1/products/categories")
async def list_categories():
    """List all product categories."""
    return {"categories": MOCK_CATEGORIES}


@app.get("/api/v1/products/{product_id}")
async def get_product(product_id: str):
    """Get a single product by ID."""
    if _db_connected:
        try:
            db = get_db()
            doc = await db["products"].find_one({"productId": product_id})
            if doc:
                doc["_id"] = str(doc["_id"])
                return doc
        except Exception as e:
            logger.warning(f"DocumentDB query failed: {e}, using fallback mock data")
    # Fallback to mock data
    for product in MOCK_PRODUCTS:
        if product["id"] == product_id:
            return product
    raise HTTPException(status_code=404, detail="상품을 찾을 수 없습니다")


@app.post("/api/v1/products")
async def create_product(product: dict):
    """Create a new product (stub - returns mock response)."""
    return {
        "id": "PRD-NEW-001",
        "name": product.get("name", "새 상품"),
        "price": product.get("price", 0),
        "category": product.get("category", "uncategorized"),
        "description": product.get("description", ""),
        "stock": product.get("stock", 0),
        "created": True,
        "message": "상품이 등록되었습니다",
    }


@app.on_event("startup")
async def startup():
    global _db_connected
    if config.documentdb_host != "localhost":
        try:
            await connect(config.documentdb_uri, config.db_name or "mall")
            _db_connected = True
            logger.info("Connected to DocumentDB")
        except Exception as e:
            logger.warning(f"DocumentDB unavailable: {e}, using fallback mock data")
    set_started(True)
    set_ready(True)


@app.on_event("shutdown")
async def shutdown():
    await disconnect()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=config.port)
