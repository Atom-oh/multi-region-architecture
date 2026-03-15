package com.mall.warehouse.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mall.warehouse.dto.AllocationResponse;
import com.mall.warehouse.dto.InventoryResponse;
import com.mall.warehouse.dto.WarehouseResponse;
import com.mall.warehouse.model.Allocation;
import com.mall.warehouse.model.AllocationStatus;
import com.mall.warehouse.model.Warehouse;
import com.mall.warehouse.repository.AllocationRepository;
import com.mall.warehouse.repository.WarehouseRepository;

@Service
public class WarehouseService {

    private static final Logger logger = LoggerFactory.getLogger(WarehouseService.class);

    private final WarehouseRepository warehouseRepository;
    private final AllocationRepository allocationRepository;

    public WarehouseService(WarehouseRepository warehouseRepository, AllocationRepository allocationRepository) {
        this.warehouseRepository = warehouseRepository;
        this.allocationRepository = allocationRepository;
    }

    public List<WarehouseResponse> listWarehouses() {
        return warehouseRepository.findByActiveTrue().stream()
                .map(WarehouseResponse::from)
                .toList();
    }

    public Optional<WarehouseResponse> getWarehouse(UUID id) {
        return warehouseRepository.findById(id)
                .map(WarehouseResponse::from);
    }

    @Transactional
    public AllocationResponse allocateOrder(UUID warehouseId, UUID orderId) {
        Warehouse warehouse = warehouseRepository.findById(warehouseId)
                .orElseThrow(() -> new IllegalArgumentException("Warehouse not found: " + warehouseId));

        Allocation allocation = new Allocation();
        allocation.setWarehouse(warehouse);
        allocation.setOrderId(orderId);
        allocation.setStatus(AllocationStatus.ALLOCATED);

        allocation = allocationRepository.save(allocation);
        logger.info("Allocated order {} to warehouse {}", orderId, warehouseId);

        return AllocationResponse.from(allocation);
    }

    @Transactional
    public AllocationResponse allocateOrderToNearestWarehouse(UUID orderId) {
        List<Warehouse> activeWarehouses = warehouseRepository.findByActiveTrue();
        if (activeWarehouses.isEmpty()) {
            throw new IllegalStateException("No active warehouses available");
        }

        // Find warehouse with most available capacity
        Warehouse selectedWarehouse = null;
        long maxAvailable = -1;

        for (Warehouse warehouse : activeWarehouses) {
            Long activeCount = allocationRepository.countActiveByWarehouseId(warehouse.getId());
            long available = warehouse.getCapacity() - activeCount;
            if (available > maxAvailable) {
                maxAvailable = available;
                selectedWarehouse = warehouse;
            }
        }

        if (selectedWarehouse == null || maxAvailable <= 0) {
            throw new IllegalStateException("All warehouses are at capacity");
        }

        return allocateOrder(selectedWarehouse.getId(), orderId);
    }

    @Transactional
    public Optional<AllocationResponse> updateAllocationStatus(UUID allocationId, AllocationStatus status) {
        return allocationRepository.findById(allocationId)
                .map(allocation -> {
                    allocation.setStatus(status);
                    allocation = allocationRepository.save(allocation);
                    logger.info("Updated allocation {} status to {}", allocationId, status);
                    return AllocationResponse.from(allocation);
                });
    }

    public InventoryResponse getWarehouseInventory(UUID warehouseId) {
        Warehouse warehouse = warehouseRepository.findById(warehouseId)
                .orElseThrow(() -> new IllegalArgumentException("Warehouse not found: " + warehouseId));

        Long activeAllocations = allocationRepository.countActiveByWarehouseId(warehouseId);
        long availableCapacity = warehouse.getCapacity() - activeAllocations;

        return new InventoryResponse(
                warehouse.getId(),
                warehouse.getName(),
                warehouse.getCapacity(),
                activeAllocations,
                Math.max(0, availableCapacity));
    }
}
