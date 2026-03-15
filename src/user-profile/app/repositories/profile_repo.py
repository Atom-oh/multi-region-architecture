"""Profile repository for DocumentDB operations."""

import logging
from datetime import datetime
from typing import Optional
from uuid import uuid4

from mall_common.documentdb import get_db

from app.models.profile import Address, AddressCreate, AddressUpdate, ProfileUpdate, UserProfile

logger = logging.getLogger(__name__)

COLLECTION = "profiles"


async def get_profile(user_id: str) -> Optional[UserProfile]:
    db = get_db()
    doc = await db[COLLECTION].find_one({"user_id": user_id})
    if doc:
        doc.pop("_id", None)
        return UserProfile(**doc)
    return None


async def create_profile(user_id: str) -> UserProfile:
    db = get_db()
    profile = UserProfile(user_id=user_id)
    await db[COLLECTION].insert_one(profile.model_dump())
    logger.info("Created profile for user: %s", user_id)
    return profile


async def update_profile(user_id: str, update: ProfileUpdate) -> Optional[UserProfile]:
    db = get_db()
    update_data = {k: v for k, v in update.model_dump().items() if v is not None}
    update_data["updated_at"] = datetime.utcnow()

    result = await db[COLLECTION].find_one_and_update(
        {"user_id": user_id},
        {"$set": update_data},
        return_document=True,
    )
    if result:
        result.pop("_id", None)
        return UserProfile(**result)
    return None


async def get_or_create_profile(user_id: str) -> UserProfile:
    profile = await get_profile(user_id)
    if profile is None:
        profile = await create_profile(user_id)
    return profile


async def get_addresses(user_id: str) -> list[Address]:
    profile = await get_profile(user_id)
    if profile:
        return profile.addresses
    return []


async def add_address(user_id: str, address: AddressCreate) -> Address:
    db = get_db()
    new_address = Address(id=str(uuid4()), **address.model_dump())

    await get_or_create_profile(user_id)

    if new_address.is_default:
        await db[COLLECTION].update_one(
            {"user_id": user_id},
            {"$set": {"addresses.$[].is_default": False}},
        )

    await db[COLLECTION].update_one(
        {"user_id": user_id},
        {
            "$push": {"addresses": new_address.model_dump()},
            "$set": {"updated_at": datetime.utcnow()},
        },
    )
    logger.info("Added address %s for user %s", new_address.id, user_id)
    return new_address


async def update_address(user_id: str, address_id: str, update: AddressUpdate) -> Optional[Address]:
    db = get_db()
    profile = await get_profile(user_id)
    if not profile:
        return None

    address_idx = None
    for idx, addr in enumerate(profile.addresses):
        if addr.id == address_id:
            address_idx = idx
            break

    if address_idx is None:
        return None

    update_data = {k: v for k, v in update.model_dump().items() if v is not None}

    if update_data.get("is_default"):
        await db[COLLECTION].update_one(
            {"user_id": user_id},
            {"$set": {"addresses.$[].is_default": False}},
        )

    set_fields = {f"addresses.{address_idx}.{k}": v for k, v in update_data.items()}
    set_fields["updated_at"] = datetime.utcnow()

    await db[COLLECTION].update_one({"user_id": user_id}, {"$set": set_fields})

    updated_profile = await get_profile(user_id)
    if updated_profile:
        for addr in updated_profile.addresses:
            if addr.id == address_id:
                return addr
    return None


async def delete_address(user_id: str, address_id: str) -> bool:
    db = get_db()
    result = await db[COLLECTION].update_one(
        {"user_id": user_id},
        {
            "$pull": {"addresses": {"id": address_id}},
            "$set": {"updated_at": datetime.utcnow()},
        },
    )
    deleted = result.modified_count > 0
    if deleted:
        logger.info("Deleted address %s for user %s", address_id, user_id)
    return deleted
