"""Product Catalog Service - FastAPI Application."""

from fastapi import FastAPI, HTTPException
from mall_common.config import ServiceConfig
from mall_common.health import router as health_router, set_ready, set_started
from mall_common.tracing import init_tracing

config = ServiceConfig(service_name="product-catalog")
app = FastAPI(title="Product Catalog Service", version="1.0.0")

init_tracing(config.service_name, app)
app.include_router(health_router)

# Mock data
MOCK_PRODUCTS = [
    {"id": "prod-001", "name": "Wireless Headphones", "price": 79.99, "category": "electronics", "description": "Premium wireless headphones with noise cancellation", "stock": 150},
    {"id": "prod-002", "name": "Running Shoes", "price": 129.99, "category": "sports", "description": "Lightweight running shoes for marathon training", "stock": 75},
    {"id": "prod-003", "name": "Coffee Maker", "price": 49.99, "category": "home", "description": "12-cup programmable coffee maker", "stock": 200},
    {"id": "prod-004", "name": "Laptop Stand", "price": 39.99, "category": "electronics", "description": "Adjustable aluminum laptop stand", "stock": 300},
    {"id": "prod-005", "name": "Yoga Mat", "price": 29.99, "category": "sports", "description": "Non-slip yoga mat with carrying strap", "stock": 120},
]

MOCK_CATEGORIES = ["electronics", "sports", "home", "clothing", "books", "toys"]


@app.get("/")
async def root():
    return {"service": "product-catalog", "status": "running"}


@app.get("/api/v1/products")
async def list_products(category: str = None, limit: int = 10, offset: int = 0):
    """List all products with optional category filter."""
    products = MOCK_PRODUCTS
    if category:
        products = [p for p in products if p["category"] == category]
    return {
        "products": products[offset:offset + limit],
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
    for product in MOCK_PRODUCTS:
        if product["id"] == product_id:
            return product
    raise HTTPException(status_code=404, detail="Product not found")


@app.post("/api/v1/products")
async def create_product(product: dict):
    """Create a new product (stub - returns mock response)."""
    return {
        "id": "prod-new-001",
        "name": product.get("name", "New Product"),
        "price": product.get("price", 0.0),
        "category": product.get("category", "uncategorized"),
        "description": product.get("description", ""),
        "stock": product.get("stock", 0),
        "created": True,
    }


@app.on_event("startup")
async def startup():
    set_started(True)
    set_ready(True)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=config.port)
