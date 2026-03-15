package com.mall.seller.repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.seller.model.SellerProduct;

@Repository
public interface SellerProductRepository extends JpaRepository<SellerProduct, UUID> {
    List<SellerProduct> findBySellerId(UUID sellerId);
    List<SellerProduct> findBySellerIdAndActiveTrue(UUID sellerId);
    Optional<SellerProduct> findBySku(String sku);
}
