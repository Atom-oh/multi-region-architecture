package com.mall.warehouse.dto;

import java.time.LocalDateTime;
import java.util.UUID;

import com.mall.warehouse.model.Allocation;
import com.mall.warehouse.model.AllocationStatus;

public record AllocationResponse(
        UUID id,
        UUID warehouseId,
        String warehouseName,
        UUID orderId,
        AllocationStatus status,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {

    public static AllocationResponse from(Allocation allocation) {
        return new AllocationResponse(
                allocation.getId(),
                allocation.getWarehouse() != null ? allocation.getWarehouse().getId() : null,
                allocation.getWarehouse() != null ? allocation.getWarehouse().getName() : null,
                allocation.getOrderId(),
                allocation.getStatus(),
                allocation.getCreatedAt(),
                allocation.getUpdatedAt());
    }
}
