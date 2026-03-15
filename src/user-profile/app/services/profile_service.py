"""Profile service - business logic."""

from typing import Optional

from app.models.profile import Address, AddressCreate, AddressUpdate, ProfileUpdate, UserProfile
from app.repositories import profile_repo


async def get_profile(user_id: str) -> Optional[UserProfile]:
    return await profile_repo.get_or_create_profile(user_id)


async def update_profile(user_id: str, update: ProfileUpdate) -> Optional[UserProfile]:
    await profile_repo.get_or_create_profile(user_id)
    return await profile_repo.update_profile(user_id, update)


async def get_addresses(user_id: str) -> list[Address]:
    return await profile_repo.get_addresses(user_id)


async def add_address(user_id: str, address: AddressCreate) -> Address:
    return await profile_repo.add_address(user_id, address)


async def update_address(user_id: str, address_id: str, update: AddressUpdate) -> Optional[Address]:
    return await profile_repo.update_address(user_id, address_id, update)


async def delete_address(user_id: str, address_id: str) -> bool:
    return await profile_repo.delete_address(user_id, address_id)
