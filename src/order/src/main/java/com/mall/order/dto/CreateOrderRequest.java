package com.mall.order.dto;

import java.math.BigDecimal;
import java.util.List;

public record CreateOrderRequest(
        String userId,
        List<OrderItemRequest> items
) {
    public record OrderItemRequest(
            String productId,
            String sku,
            Integer quantity,
            BigDecimal price
    ) {
    }
}
