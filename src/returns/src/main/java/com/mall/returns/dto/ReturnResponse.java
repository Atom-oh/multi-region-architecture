package com.mall.returns.dto;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import com.mall.returns.model.ReturnRequest;
import com.mall.returns.model.ReturnStatus;

public record ReturnResponse(
        UUID id,
        UUID orderId,
        String userId,
        String reason,
        ReturnStatus status,
        List<ReturnItemResponse> items,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {

    public static ReturnResponse from(ReturnRequest request) {
        return new ReturnResponse(
                request.getId(),
                request.getOrderId(),
                request.getUserId(),
                request.getReason(),
                request.getStatus(),
                request.getItems().stream().map(ReturnItemResponse::from).toList(),
                request.getCreatedAt(),
                request.getUpdatedAt());
    }
}
