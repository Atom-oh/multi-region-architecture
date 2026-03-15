package com.mall.warehouse.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import com.mall.warehouse.model.Allocation;
import com.mall.warehouse.model.AllocationStatus;

@Repository
public interface AllocationRepository extends JpaRepository<Allocation, UUID> {

    List<Allocation> findByWarehouseId(UUID warehouseId);

    List<Allocation> findByOrderId(UUID orderId);

    List<Allocation> findByWarehouseIdAndStatus(UUID warehouseId, AllocationStatus status);

    @Query("SELECT COUNT(a) FROM Allocation a WHERE a.warehouse.id = :warehouseId AND a.status NOT IN ('SHIPPED')")
    Long countActiveByWarehouseId(@Param("warehouseId") UUID warehouseId);
}
