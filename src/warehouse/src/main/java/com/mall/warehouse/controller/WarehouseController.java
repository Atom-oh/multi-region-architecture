package com.mall.warehouse.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mall.warehouse.dto.AllocateRequest;
import com.mall.warehouse.dto.AllocationResponse;
import com.mall.warehouse.dto.InventoryResponse;
import com.mall.warehouse.dto.WarehouseResponse;
import com.mall.warehouse.service.WarehouseService;

@RestController
@RequestMapping("/api/v1/warehouses")
public class WarehouseController {

    private final WarehouseService warehouseService;

    public WarehouseController(WarehouseService warehouseService) {
        this.warehouseService = warehouseService;
    }

    @GetMapping
    public List<WarehouseResponse> listWarehouses() {
        return warehouseService.listWarehouses();
    }

    @GetMapping("/{id}")
    public ResponseEntity<WarehouseResponse> getWarehouse(@PathVariable UUID id) {
        return warehouseService.getWarehouse(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping("/{id}/allocate")
    public ResponseEntity<AllocationResponse> allocateOrder(
            @PathVariable UUID id,
            @RequestBody AllocateRequest request) {
        try {
            AllocationResponse response = warehouseService.allocateOrder(id, request.orderId());
            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        } catch (IllegalStateException e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/{id}/inventory")
    public ResponseEntity<InventoryResponse> getWarehouseInventory(@PathVariable UUID id) {
        try {
            InventoryResponse response = warehouseService.getWarehouseInventory(id);
            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.notFound().build();
        }
    }
}
