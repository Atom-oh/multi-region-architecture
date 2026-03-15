package com.mall.warehouse.dto;

import java.util.UUID;

public record InventoryResponse(
        UUID warehouseId,
        String warehouseName,
        Integer totalCapacity,
        Long activeAllocations,
        Long availableCapacity) {
}
