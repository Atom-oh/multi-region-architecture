"""Profile service - business logic with cache-aside pattern."""

import logging
from typing import Optional

from mall_common import valkey

from app.models.profile import Address, AddressCreate, AddressUpdate, ProfileUpdate, UserProfile
from app.repositories import profile_repo

logger = logging.getLogger(__name__)

CACHE_TTL = 1800  # 30 minutes for user profiles


def _cache_key(user_id: str) -> str:
    return f"profile:{user_id}"


async def get_profile(user_id: str) -> Optional[UserProfile]:
    cache_key = _cache_key(user_id)
    cached = await valkey.get_json(cache_key)
    if cached:
        logger.debug("Cache hit for profile %s", user_id)
        return UserProfile(**cached)

    profile = await profile_repo.get_or_create_profile(user_id)
    if profile:
        await valkey.set_json(cache_key, profile.model_dump(mode="json"), CACHE_TTL)
    return profile


async def update_profile(user_id: str, update: ProfileUpdate) -> Optional[UserProfile]:
    await profile_repo.get_or_create_profile(user_id)
    profile = await profile_repo.update_profile(user_id, update)
    if profile:
        await valkey.delete(_cache_key(user_id))
    return profile


async def get_addresses(user_id: str) -> list[Address]:
    return await profile_repo.get_addresses(user_id)


async def add_address(user_id: str, address: AddressCreate) -> Address:
    address = await profile_repo.add_address(user_id, address)
    await valkey.delete(_cache_key(user_id))
    return address


async def update_address(user_id: str, address_id: str, update: AddressUpdate) -> Optional[Address]:
    result = await profile_repo.update_address(user_id, address_id, update)
    if result:
        await valkey.delete(_cache_key(user_id))
    return result


async def delete_address(user_id: str, address_id: str) -> bool:
    deleted = await profile_repo.delete_address(user_id, address_id)
    if deleted:
        await valkey.delete(_cache_key(user_id))
    return deleted
