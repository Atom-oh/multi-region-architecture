package com.mall.seller.service;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.mall.seller.dto.RegisterSellerRequest;
import com.mall.seller.dto.SellerProductRequest;
import com.mall.seller.dto.SellerProductResponse;
import com.mall.seller.dto.SellerResponse;
import com.mall.seller.model.Seller;
import com.mall.seller.model.SellerProduct;
import com.mall.seller.repository.SellerProductRepository;
import com.mall.seller.repository.SellerRepository;

@Service
public class SellerService {

    private static final Logger logger = LoggerFactory.getLogger(SellerService.class);

    private final SellerRepository sellerRepository;
    private final SellerProductRepository productRepository;

    public SellerService(SellerRepository sellerRepository, SellerProductRepository productRepository) {
        this.sellerRepository = sellerRepository;
        this.productRepository = productRepository;
    }

    @Transactional
    public SellerResponse registerSeller(RegisterSellerRequest request) {
        if (sellerRepository.existsByEmail(request.getEmail())) {
            throw new IllegalArgumentException("Email already registered");
        }

        Seller seller = new Seller();
        seller.setBusinessName(request.getBusinessName());
        seller.setEmail(request.getEmail());
        seller.setPhone(request.getPhone());
        seller.setStatus(Seller.Status.PENDING);

        Seller saved = sellerRepository.save(seller);
        logger.info("Registered new seller: {} ({})", saved.getBusinessName(), saved.getId());

        return new SellerResponse(saved);
    }

    public Optional<SellerResponse> getSellerById(UUID id) {
        return sellerRepository.findById(id).map(SellerResponse::new);
    }

    public List<SellerResponse> getAllSellers() {
        return sellerRepository.findAll().stream()
                .map(SellerResponse::new)
                .toList();
    }

    @Transactional
    public SellerProductResponse addProduct(UUID sellerId, SellerProductRequest request) {
        Seller seller = sellerRepository.findById(sellerId)
                .orElseThrow(() -> new IllegalArgumentException("Seller not found"));

        SellerProduct product = new SellerProduct();
        product.setSeller(seller);
        product.setProductId(request.getProductId());
        product.setSku(request.getSku());
        product.setPrice(request.getPrice());
        product.setStock(request.getStock() != null ? request.getStock() : 0);
        product.setActive(true);

        SellerProduct saved = productRepository.save(product);
        logger.info("Added product {} to seller {}", saved.getSku(), sellerId);

        return new SellerProductResponse(saved);
    }

    public List<SellerProductResponse> getSellerProducts(UUID sellerId) {
        return productRepository.findBySellerIdAndActiveTrue(sellerId).stream()
                .map(SellerProductResponse::new)
                .toList();
    }
}
