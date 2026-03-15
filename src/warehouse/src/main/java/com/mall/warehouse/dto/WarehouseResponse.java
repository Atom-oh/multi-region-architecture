package com.mall.warehouse.dto;

import java.time.LocalDateTime;
import java.util.UUID;

import com.mall.warehouse.model.Warehouse;

public record WarehouseResponse(
        UUID id,
        String name,
        String location,
        Integer capacity,
        Boolean active,
        LocalDateTime createdAt) {

    public static WarehouseResponse from(Warehouse warehouse) {
        return new WarehouseResponse(
                warehouse.getId(),
                warehouse.getName(),
                warehouse.getLocation(),
                warehouse.getCapacity(),
                warehouse.getActive(),
                warehouse.getCreatedAt());
    }
}
