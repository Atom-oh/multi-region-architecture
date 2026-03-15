"""Review API routes."""

from fastapi import APIRouter, HTTPException, Query

from app.models.review import Review, ReviewCreate, ReviewListResponse, ReviewUpdate
from app.services import review_service

router = APIRouter(prefix="/api/v1/reviews", tags=["reviews"])


@router.get("/product/{product_id}", response_model=ReviewListResponse)
async def get_reviews_by_product(
    product_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
):
    return await review_service.get_reviews_by_product(product_id, page, page_size)


@router.get("/{review_id}", response_model=Review)
async def get_review(review_id: str):
    review = await review_service.get_review(review_id)
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    return review


@router.post("", response_model=Review, status_code=201)
async def create_review(data: ReviewCreate):
    return await review_service.create_review(data)


@router.put("/{review_id}", response_model=Review)
async def update_review(review_id: str, update: ReviewUpdate):
    review = await review_service.update_review(review_id, update)
    if not review:
        raise HTTPException(status_code=404, detail="Review not found")
    return review


@router.delete("/{review_id}", status_code=204)
async def delete_review(review_id: str):
    deleted = await review_service.delete_review(review_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Review not found")
