package com.mall.pricing.service;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;

import com.mall.pricing.dto.CalculateRequest;
import com.mall.pricing.dto.CalculateResponse;
import com.mall.pricing.dto.PriceResponse;
import com.mall.pricing.model.PricingRule;
import com.mall.pricing.model.Promotion;
import com.mall.pricing.repository.PricingRuleRepository;
import com.mall.pricing.repository.PromotionRepository;

@Service
public class PricingService {

    private static final Logger logger = LoggerFactory.getLogger(PricingService.class);
    private static final String PRICE_CACHE_PREFIX = "price:";
    private static final Duration CACHE_TTL = Duration.ofMinutes(5);

    private final PricingRuleRepository pricingRuleRepository;
    private final PromotionRepository promotionRepository;
    private final RedisTemplate<String, Object> redisTemplate;

    public PricingService(PricingRuleRepository pricingRuleRepository,
                          PromotionRepository promotionRepository,
                          RedisTemplate<String, Object> redisTemplate) {
        this.pricingRuleRepository = pricingRuleRepository;
        this.promotionRepository = promotionRepository;
        this.redisTemplate = redisTemplate;
    }

    public Optional<PriceResponse> getPriceBySku(String sku) {
        String cacheKey = PRICE_CACHE_PREFIX + sku;

        PriceResponse cached = (PriceResponse) redisTemplate.opsForValue().get(cacheKey);
        if (cached != null) {
            logger.debug("Cache hit for SKU: {}", sku);
            return Optional.of(cached);
        }

        Optional<PricingRule> ruleOpt = pricingRuleRepository.findBySkuAndActiveTrue(sku);
        if (ruleOpt.isEmpty()) {
            return Optional.empty();
        }

        PricingRule rule = ruleOpt.get();
        List<Promotion> activePromotions = promotionRepository.findActivePromotions(LocalDateTime.now());

        BigDecimal finalPrice = calculateFinalPrice(rule.getBasePrice(), activePromotions);
        BigDecimal discount = rule.getBasePrice().subtract(finalPrice);

        PriceResponse response = new PriceResponse(
                rule.getId(),
                rule.getSku(),
                rule.getBasePrice(),
                finalPrice,
                rule.getCurrency(),
                discount
        );

        redisTemplate.opsForValue().set(cacheKey, response, CACHE_TTL);
        logger.debug("Cached price for SKU: {} with TTL: {}", sku, CACHE_TTL);

        return Optional.of(response);
    }

    public CalculateResponse calculateCartPrice(CalculateRequest request) {
        List<PriceResponse> itemPrices = new ArrayList<>();
        BigDecimal subtotal = BigDecimal.ZERO;
        BigDecimal totalDiscount = BigDecimal.ZERO;
        String currency = "USD";

        for (CalculateRequest.CartItem item : request.getItems()) {
            Optional<PriceResponse> priceOpt = getPriceBySku(item.getSku());
            if (priceOpt.isPresent()) {
                PriceResponse price = priceOpt.get();
                BigDecimal quantity = BigDecimal.valueOf(item.getQuantity());

                PriceResponse itemPrice = new PriceResponse(
                        price.getId(),
                        price.getSku(),
                        price.getBasePrice().multiply(quantity),
                        price.getFinalPrice().multiply(quantity),
                        price.getCurrency(),
                        price.getDiscountApplied().multiply(quantity)
                );

                itemPrices.add(itemPrice);
                subtotal = subtotal.add(itemPrice.getBasePrice());
                totalDiscount = totalDiscount.add(itemPrice.getDiscountApplied());
                currency = price.getCurrency();
            }
        }

        BigDecimal total = subtotal.subtract(totalDiscount);

        return new CalculateResponse(itemPrices, subtotal, totalDiscount, total, currency);
    }

    public List<Promotion> getActivePromotions() {
        return promotionRepository.findActivePromotions(LocalDateTime.now());
    }

    public Promotion createPromotion(Promotion promotion) {
        Promotion saved = promotionRepository.save(promotion);
        logger.info("Created promotion: {} ({})", saved.getName(), saved.getId());
        invalidatePriceCache();
        return saved;
    }

    private BigDecimal calculateFinalPrice(BigDecimal basePrice, List<Promotion> promotions) {
        BigDecimal finalPrice = basePrice;

        for (Promotion promo : promotions) {
            if (basePrice.compareTo(promo.getMinPurchase()) >= 0) {
                if (promo.getDiscountType() == Promotion.DiscountType.PERCENTAGE) {
                    BigDecimal discountAmount = basePrice.multiply(promo.getDiscountValue())
                            .divide(BigDecimal.valueOf(100), 2, RoundingMode.HALF_UP);
                    finalPrice = finalPrice.subtract(discountAmount);
                } else {
                    finalPrice = finalPrice.subtract(promo.getDiscountValue());
                }
            }
        }

        return finalPrice.max(BigDecimal.ZERO);
    }

    private void invalidatePriceCache() {
        logger.info("Invalidating price cache due to promotion change");
    }
}
