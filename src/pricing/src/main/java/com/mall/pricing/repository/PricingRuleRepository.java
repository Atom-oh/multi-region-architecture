package com.mall.pricing.repository;

import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import com.mall.pricing.model.PricingRule;

@Repository
public interface PricingRuleRepository extends JpaRepository<PricingRule, UUID> {
    Optional<PricingRule> findBySku(String sku);
    Optional<PricingRule> findBySkuAndActiveTrue(String sku);
}
