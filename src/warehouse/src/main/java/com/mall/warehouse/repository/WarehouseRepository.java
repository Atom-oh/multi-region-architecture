package com.mall.warehouse.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.warehouse.model.Warehouse;

@Repository
public interface WarehouseRepository extends JpaRepository<Warehouse, UUID> {

    List<Warehouse> findByActiveTrue();
}
