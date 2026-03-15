package com.mall.returns.dto;

import java.util.UUID;

import com.mall.returns.model.ReturnItem;

public record ReturnItemResponse(
        UUID id,
        String productId,
        String sku,
        Integer quantity,
        String reason) {

    public static ReturnItemResponse from(ReturnItem item) {
        return new ReturnItemResponse(
                item.getId(),
                item.getProductId(),
                item.getSku(),
                item.getQuantity(),
                item.getReason());
    }
}
