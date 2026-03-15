package com.mall.returns.repository;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.returns.model.ReturnItem;

@Repository
public interface ReturnItemRepository extends JpaRepository<ReturnItem, UUID> {
}
