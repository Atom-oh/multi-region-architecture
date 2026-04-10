"""DocumentDB repository for products and categories."""

from datetime import datetime
from typing import Optional

from bson import ObjectId
from motor.motor_asyncio import AsyncIOMotorDatabase

from mall_common.documentdb import get_db


class ProductRepository:
    def __init__(self):
        self._db: Optional[AsyncIOMotorDatabase] = None

    @property
    def db(self) -> AsyncIOMotorDatabase:
        if self._db is None:
            self._db = get_db()
        return self._db

    @property
    def products(self):
        return self.db["products"]

    @property
    def categories(self):
        return self.db["categories"]

    async def list_products(
        self,
        skip: int = 0,
        limit: int = 20,
        category_slug: Optional[str] = None,
        query: Optional[str] = None,
    ) -> list[dict]:
        filter_dict: dict = {}
        if category_slug:
            filter_dict["category.slug"] = category_slug
        if query:
            filter_dict["name"] = {"$regex": query, "$options": "i"}

        total = await self.products.count_documents(filter_dict)
        cursor = self.products.find(filter_dict).skip(skip).limit(limit)
        products = []
        async for doc in cursor:
            doc["_id"] = str(doc["_id"])
            products.append(doc)
        return products, total

    async def get_product(self, product_id: str) -> Optional[dict]:
        doc = await self.products.find_one({"productId": product_id})
        if doc:
            doc["_id"] = str(doc["_id"])
        return doc

    async def get_product_by_sku(self, sku: str) -> Optional[dict]:
        doc = await self.products.find_one({"sku": sku})
        if doc:
            doc["_id"] = str(doc["_id"])
        return doc

    async def create_product(self, product_data: dict) -> dict:
        product_data["created_at"] = datetime.utcnow()
        product_data["updated_at"] = datetime.utcnow()
        result = await self.products.insert_one(product_data)
        product_data["_id"] = str(result.inserted_id)
        return product_data

    async def update_product(self, product_id: str, update_data: dict) -> Optional[dict]:
        update_data["updated_at"] = datetime.utcnow()
        await self.products.update_one(
            {"_id": ObjectId(product_id)},
            {"$set": update_data},
        )
        return await self.get_product(product_id)

    async def delete_product(self, product_id: str) -> bool:
        result = await self.products.delete_one({"_id": ObjectId(product_id)})
        return result.deleted_count > 0

    async def list_categories(self) -> list[dict]:
        cursor = self.categories.find()
        categories = []
        async for doc in cursor:
            doc["_id"] = str(doc["_id"])
            categories.append(doc)
        return categories

    async def get_category(self, category_id: str) -> Optional[dict]:
        doc = await self.categories.find_one({"_id": ObjectId(category_id)})
        if doc:
            doc["_id"] = str(doc["_id"])
        return doc

    async def create_category(self, category_data: dict) -> dict:
        category_data["created_at"] = datetime.utcnow()
        result = await self.categories.insert_one(category_data)
        category_data["_id"] = str(result.inserted_id)
        return category_data


product_repo = ProductRepository()
