package com.mall.seller.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.mall.seller.dto.DocumentUploadRequest;
import com.mall.seller.dto.DocumentUploadResponse;
import com.mall.seller.dto.RegisterSellerRequest;
import com.mall.seller.dto.SellerProductRequest;
import com.mall.seller.dto.SellerProductResponse;
import com.mall.seller.dto.SellerResponse;
import com.mall.seller.service.S3Service;
import com.mall.seller.service.SellerService;

@RestController
@RequestMapping("/api/v1/sellers")
public class SellerController {

    private final SellerService sellerService;
    private final S3Service s3Service;

    public SellerController(SellerService sellerService, S3Service s3Service) {
        this.sellerService = sellerService;
        this.s3Service = s3Service;
    }

    @PostMapping("/register")
    public ResponseEntity<SellerResponse> registerSeller(@RequestBody RegisterSellerRequest request) {
        SellerResponse response = sellerService.registerSeller(request);
        return ResponseEntity.status(201).body(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<SellerResponse> getSeller(@PathVariable UUID id) {
        return sellerService.getSellerById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping
    public ResponseEntity<List<SellerResponse>> listSellers() {
        List<SellerResponse> sellers = sellerService.getAllSellers();
        return ResponseEntity.ok(sellers);
    }

    @PostMapping("/{id}/products")
    public ResponseEntity<SellerProductResponse> addProduct(@PathVariable UUID id, @RequestBody SellerProductRequest request) {
        SellerProductResponse response = sellerService.addProduct(id, request);
        return ResponseEntity.status(201).body(response);
    }

    @GetMapping("/{id}/products")
    public ResponseEntity<List<SellerProductResponse>> getSellerProducts(@PathVariable UUID id) {
        List<SellerProductResponse> products = sellerService.getSellerProducts(id);
        return ResponseEntity.ok(products);
    }

    @PostMapping("/{id}/documents")
    public ResponseEntity<DocumentUploadResponse> uploadDocument(@PathVariable UUID id, @RequestBody DocumentUploadRequest request) {
        DocumentUploadResponse response = s3Service.generatePresignedUploadUrl(id, request);
        return ResponseEntity.ok(response);
    }
}
