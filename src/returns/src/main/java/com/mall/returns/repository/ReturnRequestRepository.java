package com.mall.returns.repository;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.returns.model.ReturnRequest;

@Repository
public interface ReturnRequestRepository extends JpaRepository<ReturnRequest, UUID> {

    List<ReturnRequest> findByUserId(String userId);

    List<ReturnRequest> findByOrderId(UUID orderId);
}
