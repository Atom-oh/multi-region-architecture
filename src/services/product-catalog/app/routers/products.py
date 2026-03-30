"""Products API router."""

from typing import Optional

from fastapi import APIRouter, HTTPException, Query

from app.models.product import Product, ProductCreate, ProductUpdate
from app.services import product_service

router = APIRouter(prefix="/api/v1", tags=["products"])


@router.get("/products")
async def list_products(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    category: Optional[str] = Query(None),
    q: Optional[str] = Query(None),
):
    products = await product_service.list_products(
        skip=skip,
        limit=limit,
        category_id=category,
        query=q,
    )
    return {"products": products, "skip": skip, "limit": limit}


@router.get("/products/categories")
async def list_categories():
    categories = await product_service.list_categories()
    return {"categories": categories}


@router.get("/products/{product_id}")
async def get_product(product_id: str):
    product = await product_service.get_product(product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


@router.post("/products", status_code=201)
async def create_product(product: ProductCreate):
    product_data = product.model_dump()
    created = await product_service.create_product(product_data)
    return created


@router.put("/products/{product_id}")
async def update_product(product_id: str, product: ProductUpdate):
    update_data = product.model_dump(exclude_unset=True)
    updated = await product_service.update_product(product_id, update_data)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found")
    return updated


@router.delete("/products/{product_id}", status_code=204)
async def delete_product(product_id: str):
    deleted = await product_service.delete_product(product_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Product not found")
    return None
