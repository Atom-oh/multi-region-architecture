"""Profile API routes."""

from fastapi import APIRouter, HTTPException

from app.models.profile import Address, AddressCreate, AddressUpdate, ProfileUpdate, UserProfile
from app.services import profile_service

router = APIRouter(prefix="/api/v1/profiles", tags=["profiles"])


@router.get("/{user_id}", response_model=UserProfile)
async def get_profile(user_id: str):
    profile = await profile_service.get_profile(user_id)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.put("/{user_id}", response_model=UserProfile)
async def update_profile(user_id: str, update: ProfileUpdate):
    profile = await profile_service.update_profile(user_id, update)
    if not profile:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile


@router.get("/{user_id}/addresses", response_model=list[Address])
async def get_addresses(user_id: str):
    return await profile_service.get_addresses(user_id)


@router.post("/{user_id}/addresses", response_model=Address, status_code=201)
async def add_address(user_id: str, address: AddressCreate):
    return await profile_service.add_address(user_id, address)


@router.put("/{user_id}/addresses/{address_id}", response_model=Address)
async def update_address(user_id: str, address_id: str, update: AddressUpdate):
    address = await profile_service.update_address(user_id, address_id, update)
    if not address:
        raise HTTPException(status_code=404, detail="Address not found")
    return address


@router.delete("/{user_id}/addresses/{address_id}", status_code=204)
async def delete_address(user_id: str, address_id: str):
    deleted = await profile_service.delete_address(user_id, address_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Address not found")
