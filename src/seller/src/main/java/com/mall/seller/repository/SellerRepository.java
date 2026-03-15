package com.mall.seller.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.seller.model.Seller;

@Repository
public interface SellerRepository extends JpaRepository<Seller, UUID> {
    Optional<Seller> findByEmail(String email);
    boolean existsByEmail(String email);
}
