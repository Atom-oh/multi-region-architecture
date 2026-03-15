package com.mall.returns.dto;

public record ReturnItemRequest(
        String productId,
        String sku,
        Integer quantity,
        String reason) {
}
