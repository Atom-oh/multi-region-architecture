package com.mall.order.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import com.mall.order.model.Order;
import com.mall.order.model.OrderItem;
import com.mall.order.model.OrderStatus;

public record OrderResponse(
        UUID id,
        String userId,
        OrderStatus status,
        BigDecimal totalAmount,
        List<OrderItemResponse> items,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
    public record OrderItemResponse(
            UUID id,
            String productId,
            String sku,
            Integer quantity,
            BigDecimal price
    ) {
        public static OrderItemResponse from(OrderItem item) {
            return new OrderItemResponse(
                    item.getId(),
                    item.getProductId(),
                    item.getSku(),
                    item.getQuantity(),
                    item.getPrice()
            );
        }
    }

    public static OrderResponse from(Order order) {
        return new OrderResponse(
                order.getId(),
                order.getUserId(),
                order.getStatus(),
                order.getTotalAmount(),
                order.getItems().stream().map(OrderItemResponse::from).toList(),
                order.getCreatedAt(),
                order.getUpdatedAt()
        );
    }
}
