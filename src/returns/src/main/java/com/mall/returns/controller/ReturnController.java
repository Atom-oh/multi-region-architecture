package com.mall.returns.controller;

import java.util.List;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.mall.returns.dto.CreateReturnRequest;
import com.mall.returns.dto.ReturnResponse;
import com.mall.returns.service.ReturnService;

@RestController
@RequestMapping("/api/v1/returns")
public class ReturnController {

    private final ReturnService returnService;

    public ReturnController(ReturnService returnService) {
        this.returnService = returnService;
    }

    @PostMapping
    public ResponseEntity<ReturnResponse> createReturn(@RequestBody CreateReturnRequest request) {
        ReturnResponse response = returnService.createReturn(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping("/{id}")
    public ResponseEntity<ReturnResponse> getReturn(@PathVariable UUID id) {
        return returnService.getReturn(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping
    public List<ReturnResponse> listReturns(@RequestParam String userId) {
        return returnService.getReturnsByUser(userId);
    }

    @PutMapping("/{id}/approve")
    public ResponseEntity<ReturnResponse> approveReturn(@PathVariable UUID id) {
        try {
            return returnService.approveReturn(id)
                    .map(ResponseEntity::ok)
                    .orElse(ResponseEntity.notFound().build());
        } catch (IllegalStateException e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @PutMapping("/{id}/reject")
    public ResponseEntity<ReturnResponse> rejectReturn(@PathVariable UUID id) {
        try {
            return returnService.rejectReturn(id)
                    .map(ResponseEntity::ok)
                    .orElse(ResponseEntity.notFound().build());
        } catch (IllegalStateException e) {
            return ResponseEntity.badRequest().build();
        }
    }
}
