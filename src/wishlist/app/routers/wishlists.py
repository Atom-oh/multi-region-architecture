"""Wishlist API routes."""

from fastapi import APIRouter, HTTPException

from app.models.wishlist import Wishlist, WishlistItem, WishlistItemCreate
from app.services import wishlist_service

router = APIRouter(prefix="/api/v1/wishlists", tags=["wishlists"])


@router.get("/{user_id}", response_model=Wishlist)
async def get_wishlist(user_id: str):
    return await wishlist_service.get_wishlist(user_id)


@router.post("/{user_id}/items", response_model=WishlistItem, status_code=201)
async def add_item(user_id: str, item: WishlistItemCreate):
    return await wishlist_service.add_item(user_id, item)


@router.delete("/{user_id}/items/{product_id}", status_code=204)
async def remove_item(user_id: str, product_id: str):
    removed = await wishlist_service.remove_item(user_id, product_id)
    if not removed:
        raise HTTPException(status_code=404, detail="Item not found in wishlist")
